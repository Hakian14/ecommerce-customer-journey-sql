"""
Synthetic e-commerce dataset generator.

Produces a CDP-style dataset for a Vietnamese omnichannel retailer:
customers, products, orders, order_items, payments, reviews and
clickstream web_events. Everything is generated from a fixed seed so
the dataset is fully reproducible. No real customer or company data
is used anywhere.

Usage:
    python data/generate_data.py            # writes CSVs to data/raw/
    python data/generate_data.py --scale 2  # 2x more customers/orders

Design goals (so that the SQL analyses have something real to find):
  * ~55% of customers order more than once; loyalty is heterogeneous.
  * Strong seasonality: Tet (Jan), mid-year sale (Jun), 11.11 and 12.12.
  * 2025 volume ~20% higher than 2024 (business is growing).
  * Channel mix: web, mobile app, marketplace, social commerce -
    conversion rates differ by channel.
  * ~15% of deliveries are late; late deliveries drag review scores down.
  * Clickstream funnel: page_view -> product_view -> add_to_cart ->
    checkout_start -> purchase, with realistic drop-off.
"""

from __future__ import annotations

import argparse
import os
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

SEED = 42
START = datetime(2024, 1, 1)
END = datetime(2025, 11, 30, 23, 59, 59)
DAYS = (END - START).days + 1

CITIES = [
    # city, region, weight
    ("Ho Chi Minh City", "South", 0.30),
    ("Ha Noi", "North", 0.26),
    ("Hai Phong", "North", 0.07),
    ("Da Nang", "Central", 0.07),
    ("Can Tho", "South", 0.05),
    ("Bien Hoa", "South", 0.04),
    ("Hue", "Central", 0.03),
    ("Nha Trang", "Central", 0.03),
    ("Hai Duong", "North", 0.03),
    ("Bac Ninh", "North", 0.03),
    ("Vung Tau", "South", 0.03),
    ("Quang Ninh", "North", 0.03),
    ("Vinh", "Central", 0.02),
    ("Thai Nguyen", "North", 0.01),
]

ACQ_CHANNELS = ["organic_search", "paid_social", "marketplace", "referral", "direct"]
ACQ_WEIGHTS = [0.28, 0.27, 0.22, 0.13, 0.10]

ORDER_CHANNELS = ["web", "mobile_app", "marketplace", "social_commerce"]
ORDER_CHANNEL_WEIGHTS = [0.35, 0.30, 0.25, 0.10]

# category, min price, max price (VND), margin
CATEGORIES = [
    ("Women's Fashion", 120_000, 1_500_000, 0.55),
    ("Men's Fashion", 150_000, 1_800_000, 0.52),
    ("Footwear", 250_000, 2_500_000, 0.48),
    ("Accessories", 50_000, 900_000, 0.60),
    ("Beauty & Personal Care", 60_000, 1_200_000, 0.50),
    ("Home & Living", 80_000, 3_500_000, 0.42),
    ("Kitchen", 90_000, 4_000_000, 0.40),
    ("Electronics Accessories", 40_000, 1_500_000, 0.35),
    ("Phones & Gadgets", 800_000, 25_000_000, 0.12),
    ("Baby & Kids", 70_000, 2_000_000, 0.45),
    ("Sports & Outdoors", 120_000, 3_000_000, 0.44),
    ("Books & Stationery", 25_000, 400_000, 0.38),
    ("Health & Wellness", 90_000, 1_800_000, 0.47),
    ("Pet Supplies", 40_000, 1_200_000, 0.41),
    ("Groceries", 20_000, 500_000, 0.22),
]
CATEGORY_WEIGHTS = np.array([0.14, 0.10, 0.08, 0.08, 0.11, 0.08, 0.06, 0.07, 0.03, 0.06, 0.05, 0.04, 0.04, 0.03, 0.03])

# behavioural parameters that the SQL analyses are meant to surface
LOYALTY_BY_ACQ = {"referral": 1.35, "organic_search": 1.20, "direct": 1.10, "marketplace": 0.85, "paid_social": 0.70}
ONE_TIMER_BY_ACQ = {"referral": 0.28, "organic_search": 0.33, "direct": 0.36, "marketplace": 0.42, "paid_social": 0.48}
LATE_P_BY_REGION = {"North": 0.12, "Central": 0.21, "South": 0.15}
FIRST_LATE_CHURN = 0.40          # P(drop a later order | first delivery was late)
NON_CONVERTING_SESSIONS_PER_ORDER = 9.0
NON_CONVERTING_CHANNEL_WEIGHTS = [0.34, 0.20, 0.24, 0.22]   # web, mobile_app, marketplace, social_commerce

PAYMENT_METHODS = ["cod", "e_wallet", "bank_transfer", "credit_card"]
PAYMENT_WEIGHTS = [0.40, 0.30, 0.20, 0.10]

# multiplicative seasonality by calendar month (1..12)
MONTH_SEASONALITY = {1: 1.30, 2: 0.85, 3: 0.90, 4: 0.95, 5: 1.00, 6: 1.12,
                     7: 0.95, 8: 0.95, 9: 1.00, 10: 1.05, 11: 1.45, 12: 1.35}
DOW_SEASONALITY = {0: 0.95, 1: 0.95, 2: 1.00, 3: 1.00, 4: 1.05, 5: 1.10, 6: 1.05}  # Mon..Sun
SALE_DAYS = {(11, 11): 3.0, (12, 12): 2.6, (6, 6): 1.8, (9, 9): 1.6, (10, 10): 1.6}


def day_weights() -> np.ndarray:
    """Probability that an order falls on each calendar day in the window."""
    w = np.empty(DAYS)
    for i in range(DAYS):
        d = START + timedelta(days=i)
        growth = 1.0 + 0.20 * (i / DAYS)  # ~20% growth across the window
        w[i] = MONTH_SEASONALITY[d.month] * DOW_SEASONALITY[d.weekday()] * growth
        w[i] *= SALE_DAYS.get((d.month, d.day), 1.0)
    return w / w.sum()


def gen_customers(rng: np.random.Generator, n: int) -> pd.DataFrame:
    city_idx = rng.choice(len(CITIES), size=n, p=[c[2] for c in CITIES])
    # ~45% of the base existed before the analysis window; the rest sign up during it
    existing = rng.random(n) < 0.45
    signup_offset = np.where(existing, rng.integers(-540, 0, size=n), rng.integers(0, DAYS - 30, size=n))
    signup = [START + timedelta(days=int(o)) for o in signup_offset]
    return pd.DataFrame({
        "customer_id": [f"C{100000 + i}" for i in range(n)],
        "signup_date": [d.date().isoformat() for d in signup],
        "city": [CITIES[i][0] for i in city_idx],
        "region": [CITIES[i][1] for i in city_idx],
        "acquisition_channel": rng.choice(ACQ_CHANNELS, size=n, p=ACQ_WEIGHTS),
        "age_band": rng.choice(["18-24", "25-34", "35-44", "45-54", "55+"], size=n,
                               p=[0.22, 0.40, 0.22, 0.11, 0.05]),
        "gender": rng.choice(["F", "M", "unknown"], size=n, p=[0.58, 0.37, 0.05]),
    })


def gen_products(rng: np.random.Generator, n: int) -> pd.DataFrame:
    cat_idx = rng.choice(len(CATEGORIES), size=n, p=CATEGORY_WEIGHTS / CATEGORY_WEIGHTS.sum())
    rows = []
    for i, ci in enumerate(cat_idx):
        cat, lo, hi, margin = CATEGORIES[ci]
        # log-uniform price, rounded to 1,000 VND
        price = int(round(np.exp(rng.uniform(np.log(lo), np.log(hi))) / 1000.0) * 1000)
        cost = int(round(price * (1 - margin) * rng.uniform(0.9, 1.1) / 1000.0) * 1000)
        rows.append({
            "product_id": f"P{10000 + i}",
            "category": cat,
            "product_name": f"{cat.split(' ')[0]} item {i:04d}",
            "unit_price": price,
            "unit_cost": cost,
        })
    return pd.DataFrame(rows)


def gen_orders(rng, customers: pd.DataFrame, n_orders_target: int):
    n_cust = len(customers)
    # heterogeneous loyalty: gamma-distributed expected orders per customer,
    # shifted by acquisition channel (referrals and organic stick, paid social churns)
    loyalty_mult = customers["acquisition_channel"].map(LOYALTY_BY_ACQ).to_numpy()
    loyalty = rng.gamma(shape=0.9, scale=1.0, size=n_cust) * loyalty_mult
    expected = loyalty / loyalty.sum() * n_orders_target
    n_orders_per_cust = 1 + rng.poisson(expected)
    # a channel-dependent share of customers remain one-timers regardless of latent loyalty
    one_timer_p = customers["acquisition_channel"].map(ONE_TIMER_BY_ACQ).to_numpy()
    one_timers = rng.random(n_cust) < one_timer_p
    n_orders_per_cust[one_timers] = 1

    dw = day_weights()
    signup_days = pd.to_datetime(customers["signup_date"]).map(lambda d: (d - START).days).to_numpy()

    cust_ids, order_days = [], []
    for ci in range(n_cust):
        k = int(n_orders_per_cust[ci])
        # candidate days must be after signup
        mask = np.arange(DAYS) >= max(0, signup_days[ci])
        p = dw * mask
        if p.sum() == 0:
            continue
        p = p / p.sum()
        days = np.sort(rng.choice(DAYS, size=k, p=p, replace=True))
        cust_ids.extend([ci] * k)
        order_days.extend(days.tolist())

    n = len(cust_ids)
    cust_ids = np.array(cust_ids)
    order_days = np.array(order_days)
    # time of day: skewed to evening
    hours = np.clip(rng.normal(19, 4, size=n), 0, 23.99)
    order_ts = [START + timedelta(days=int(d), hours=float(h)) for d, h in zip(order_days, hours)]

    channel = rng.choice(ORDER_CHANNELS, size=n, p=ORDER_CHANNEL_WEIGHTS)
    status = rng.choice(["delivered", "cancelled", "returned"], size=n, p=[0.92, 0.05, 0.03])
    # the most recent orders are still in transit
    recent = order_days > DAYS - 6
    status = np.where(recent & (status == "delivered"), "in_transit", status)

    promo = np.where(rng.random(n) < 0.32,
                     rng.choice(["TET2024", "TET2025", "MIDYEAR", "SALE1111", "SALE1212", "WELCOME10", "FREESHIP"], size=n),
                     None)

    est_days = rng.integers(3, 8, size=n)
    # late-delivery probability depends on the customer's region (logistics coverage)
    region = customers["region"].to_numpy()[cust_ids]
    late_p = pd.Series(region).map(LATE_P_BY_REGION).to_numpy()
    late = rng.random(n) < late_p
    delay = np.where(late, rng.integers(1, 6, size=n), rng.integers(-2, 1, size=n))
    delivered_days = est_days + delay

    # Behavioural effect: a late FIRST delivery makes customers less likely to come back.
    # Drop each subsequent order of such customers with probability FIRST_LATE_CHURN.
    order_rank = pd.Series(np.arange(n)).groupby(cust_ids).rank(method="first").to_numpy()  # days are sorted per customer
    first_late_cust = set(cust_ids[(order_rank == 1) & late & (status != "cancelled")])
    is_later_order_of_hurt_cust = np.array([(c in first_late_cust) and (r > 1) for c, r in zip(cust_ids, order_rank)])
    keep = ~(is_later_order_of_hurt_cust & (rng.random(n) < FIRST_LATE_CHURN))

    df = pd.DataFrame({
        "order_id": [f"O{1000000 + i}" for i in range(n)],
        "customer_id": customers["customer_id"].to_numpy()[cust_ids],
        "order_ts": [t.strftime("%Y-%m-%d %H:%M:%S") for t in order_ts],
        "channel": channel,
        "status": status,
        "promo_code": promo,
        # both dates are anchored on the order *date*, so late == delivered_days > est_days
        "estimated_delivery_date": [(t.date() + timedelta(days=int(e))).isoformat() for t, e in zip(order_ts, est_days)],
        "delivered_at": [
            (datetime.combine(t.date(), datetime.min.time()) + timedelta(days=int(dd), hours=float(rng.uniform(8, 20)))).strftime("%Y-%m-%d %H:%M:%S")
            if s in ("delivered", "returned") else None
            for t, dd, s in zip(order_ts, delivered_days, status)
        ],
    })
    df = df[keep].sort_values("order_ts").reset_index(drop=True)
    df["order_id"] = [f"O{1000000 + i}" for i in range(len(df))]
    return df


def gen_order_items(rng, orders: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    n_items_per_order = rng.choice([1, 2, 3, 4, 5], size=len(orders), p=[0.55, 0.25, 0.12, 0.05, 0.03])
    order_idx = np.repeat(np.arange(len(orders)), n_items_per_order)
    seq = np.concatenate([np.arange(1, k + 1) for k in n_items_per_order])
    # product popularity follows a long tail
    pop = rng.pareto(1.2, size=len(products)) + 1
    pop = pop / pop.sum()
    prod_idx = rng.choice(len(products), size=len(order_idx), p=pop)
    qty = rng.choice([1, 2, 3], size=len(order_idx), p=[0.82, 0.14, 0.04])
    has_promo = orders["promo_code"].notna().to_numpy()[order_idx]
    discount_rate = np.where(has_promo, rng.choice([0.05, 0.10, 0.15, 0.20], size=len(order_idx)), 0.0)
    unit_price = products["unit_price"].to_numpy()[prod_idx]
    return pd.DataFrame({
        "order_id": orders["order_id"].to_numpy()[order_idx],
        "item_seq": seq,
        "product_id": products["product_id"].to_numpy()[prod_idx],
        "quantity": qty,
        "unit_price": unit_price,
        "discount_amount": (unit_price * qty * discount_rate).round(-3).astype(int),
    })


def gen_payments(rng, orders: pd.DataFrame, items: pd.DataFrame) -> pd.DataFrame:
    gross = (items["unit_price"] * items["quantity"] - items["discount_amount"]).groupby(items["order_id"]).sum()
    totals = gross.reindex(orders["order_id"]).to_numpy()
    n = len(orders)
    shipping = np.where(orders["promo_code"].eq("FREESHIP"), 0, rng.choice([15_000, 25_000, 30_000, 35_000], size=n))
    method = rng.choice(PAYMENT_METHODS, size=n, p=PAYMENT_WEIGHTS)
    # marketplace orders almost never COD in this business
    method = np.where((orders["channel"] == "marketplace") & (method == "cod"), "e_wallet", method)
    installments = np.where((method == "credit_card") & (totals > 3_000_000), rng.choice([3, 6, 12], size=n), 1)
    return pd.DataFrame({
        "payment_id": [f"PAY{2000000 + i}" for i in range(n)],
        "order_id": orders["order_id"],
        "payment_method": method,
        "installments": installments,
        "shipping_fee": shipping,
        "amount": (totals + shipping).astype(int),
    })


def gen_reviews(rng, orders: pd.DataFrame) -> pd.DataFrame:
    eligible = orders[orders["status"].isin(["delivered", "returned"])].copy()
    reviewed = eligible[rng.random(len(eligible)) < 0.62].copy()
    est = pd.to_datetime(reviewed["estimated_delivery_date"])
    act = pd.to_datetime(reviewed["delivered_at"])
    late_days = (act.dt.normalize() - est).dt.days.clip(lower=0)
    base = np.where(late_days == 0, 4.35, 4.35 - 0.45 * late_days)
    base = np.where(reviewed["status"] == "returned", base - 1.6, base)
    score = np.clip(np.round(rng.normal(base, 0.75)), 1, 5).astype(int)
    created = act + pd.to_timedelta(rng.integers(0, 10, size=len(reviewed)), unit="D")
    return pd.DataFrame({
        "review_id": [f"R{3000000 + i}" for i in range(len(reviewed))],
        "order_id": reviewed["order_id"].to_numpy(),
        "review_score": score,
        "created_at": created.dt.strftime("%Y-%m-%d %H:%M:%S").to_numpy(),
    })


FUNNEL = ["page_view", "product_view", "add_to_cart", "checkout_start", "purchase"]


def gen_web_events(rng, orders: pd.DataFrame, customers: pd.DataFrame, items: pd.DataFrame) -> pd.DataFrame:
    """Converting sessions (one per order) + non-converting sessions with drop-off."""
    rows = []
    sid = 0
    first_product = items.drop_duplicates("order_id").set_index("order_id")["product_id"]

    # 1) converting sessions: full funnel ending in purchase at order_ts
    ts = pd.to_datetime(orders["order_ts"])
    for oid, cid, ch, t in zip(orders["order_id"], orders["customer_id"], orders["channel"], ts):
        sid += 1
        session = f"S{sid:07d}"
        gaps = np.cumsum(rng.uniform(40, 400, size=4))[::-1]  # seconds before purchase
        times = [t - timedelta(seconds=float(g)) for g in gaps] + [t]
        pid = first_product.get(oid)
        for ev, et in zip(FUNNEL, times):
            rows.append((session, cid, ch, et, ev, pid if ev in ("product_view", "add_to_cart") else None, oid if ev == "purchase" else None))

    # 2) non-converting sessions, drop off at a stage that depends on channel
    n_nc = int(len(orders) * NON_CONVERTING_SESSIONS_PER_ORDER)
    drop_p = {  # probability of reaching each successive stage, by channel
        "web":             [1.0, 0.62, 0.30, 0.14],
        "mobile_app":      [1.0, 0.70, 0.40, 0.22],
        "marketplace":     [1.0, 0.75, 0.38, 0.18],
        "social_commerce": [1.0, 0.50, 0.18, 0.07],
    }
    # browsing traffic is skewed toward social and web; the app converts best
    ch = rng.choice(ORDER_CHANNELS, size=n_nc, p=NON_CONVERTING_CHANNEL_WEIGHTS)
    anon = rng.random(n_nc) < 0.25
    cust = rng.choice(customers["customer_id"].to_numpy(), size=n_nc)
    cust = np.where(anon, None, cust)
    day = rng.choice(DAYS, size=n_nc, p=day_weights())
    hour = np.clip(rng.normal(19, 4, size=n_nc), 0, 23.9)
    prods = rng.choice(items["product_id"].to_numpy(), size=n_nc)
    u = rng.random((n_nc, 4))
    reach = np.array([drop_p[c] for c in ch])                      # (n_nc, 4)
    passed = u < reach                                              # stage s reached if all earlier passed
    stages = 1 + np.cumprod(passed[:, 1:], axis=1).sum(axis=1)      # 1..4 (never 'purchase')
    t0 = np.array([START + timedelta(days=int(d), hours=float(h)) for d, h in zip(day, hour)])
    for i in range(n_nc):
        sid += 1
        session = f"S{sid:07d}"
        t = t0[i]
        for ev in FUNNEL[:stages[i]]:
            rows.append((session, cust[i], ch[i], t, ev, prods[i] if ev in ("product_view", "add_to_cart") else None, None))
            t = t + timedelta(seconds=float(rng.uniform(30, 300)))

    df = pd.DataFrame(rows, columns=["session_id", "customer_id", "channel", "event_ts", "event_type", "product_id", "order_id"])
    df = df.sort_values("event_ts").reset_index(drop=True)
    df.insert(0, "event_id", np.arange(1, len(df) + 1))
    df["event_ts"] = pd.to_datetime(df["event_ts"]).dt.strftime("%Y-%m-%d %H:%M:%S")
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=float, default=1.0, help="size multiplier (1.0 ≈ 4,000 customers / 16,000 orders)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "raw"))
    args = ap.parse_args()

    rng = np.random.default_rng(SEED)
    os.makedirs(args.out, exist_ok=True)

    customers = gen_customers(rng, int(4000 * args.scale))
    products = gen_products(rng, int(320 * args.scale ** 0.5))
    orders = gen_orders(rng, customers, int(16000 * args.scale))
    items = gen_order_items(rng, orders, products)
    payments = gen_payments(rng, orders, items)
    reviews = gen_reviews(rng, orders)
    events = gen_web_events(rng, orders, customers, items)

    for name, df in [("customers", customers), ("products", products), ("orders", orders),
                     ("order_items", items), ("payments", payments), ("reviews", reviews),
                     ("web_events", events)]:
        path = os.path.join(args.out, f"{name}.csv" + (".gz" if name == "web_events" else ""))
        df.to_csv(path, index=False, compression="gzip" if name == "web_events" else None)
        print(f"{name:12s} {len(df):>8,} rows -> {path}")


if __name__ == "__main__":
    main()
