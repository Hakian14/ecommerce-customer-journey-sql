# Data dictionary

All monetary values are in Vietnamese dong (VND), stored as integers.
All timestamps are local time, ISO-8601 text (`YYYY-MM-DD HH:MM:SS`).

## customers

| Column | Type | Description | Values / rules |
|---|---|---|---|
| customer_id | TEXT | Surrogate key | `C100000`… |
| signup_date | TEXT | Date the account was created | ~45% pre-date the analysis window |
| city | TEXT | Shipping city on file | 14 Vietnamese cities |
| region | TEXT | Derived from city | `North`, `Central`, `South` |
| acquisition_channel | TEXT | First-touch channel that acquired the customer | `organic_search`, `paid_social`, `marketplace`, `referral`, `direct` |
| age_band | TEXT | Self-reported age band | `18-24` … `55+` |
| gender | TEXT | Self-reported | `F`, `M`, `unknown` |

## products

| Column | Type | Description |
|---|---|---|
| product_id | TEXT | Surrogate key, `P10000`… |
| category | TEXT | One of 15 merchandising categories |
| product_name | TEXT | Display name |
| unit_price | INTEGER | Current list price |
| unit_cost | INTEGER | Landed cost used for gross margin |

## orders

| Column | Type | Description | Values / rules |
|---|---|---|---|
| order_id | TEXT | Surrogate key, `O1000000`… | Sequential in `order_ts` |
| customer_id | TEXT | FK → customers | NOT NULL (no guest checkout in this dataset) |
| order_ts | TEXT | Timestamp the order was placed | 2024-01-01 → 2025-11-30 |
| channel | TEXT | Where the order was placed | `web`, `mobile_app`, `marketplace`, `social_commerce` |
| status | TEXT | Final state at snapshot | `delivered`, `cancelled`, `returned`, `in_transit` |
| promo_code | TEXT | Promotion applied, if any | NULL for ~68% of orders |
| estimated_delivery_date | TEXT | Promised delivery date | order date + 3..7 days |
| delivered_at | TEXT | Actual delivery timestamp | NULL unless `delivered` / `returned`. **Late** = `DATE(delivered_at) > estimated_delivery_date` |

## order_items

| Column | Type | Description |
|---|---|---|
| order_id | TEXT | FK → orders |
| item_seq | INTEGER | Line number within the order (1-based) |
| product_id | TEXT | FK → products |
| quantity | INTEGER | Units on the line (≥ 1) |
| unit_price | INTEGER | Price charged per unit at time of sale |
| discount_amount | INTEGER | Total discount on the line; `line net value = unit_price × quantity − discount_amount` |

## payments

| Column | Type | Description | Values / rules |
|---|---|---|---|
| payment_id | TEXT | Surrogate key | |
| order_id | TEXT | FK → orders (unique) | exactly one payment per order |
| payment_method | TEXT | | `cod`, `e_wallet`, `bank_transfer`, `credit_card` |
| installments | INTEGER | Number of instalments | 1 unless card payment > 3,000,000 VND |
| shipping_fee | INTEGER | Shipping charged to customer | 0 when `FREESHIP` promo applied |
| amount | INTEGER | Total charged | `= Σ line net value + shipping_fee` |

## reviews

| Column | Type | Description |
|---|---|---|
| review_id | TEXT | Surrogate key |
| order_id | TEXT | FK → orders (unique) |
| review_score | INTEGER | 1 (worst) – 5 (best) |
| created_at | TEXT | 0–9 days after delivery |

## web_events

| Column | Type | Description | Values / rules |
|---|---|---|---|
| event_id | INTEGER | Surrogate key | |
| session_id | TEXT | Groups events into a browsing session | |
| customer_id | TEXT | FK → customers | NULL for anonymous sessions (~25% of non-converting sessions) |
| channel | TEXT | Surface where the session happened | same values as `orders.channel` |
| event_ts | TEXT | Event timestamp | |
| event_type | TEXT | Funnel stage | `page_view` → `product_view` → `add_to_cart` → `checkout_start` → `purchase` |
| product_id | TEXT | Product involved | populated on `product_view` and `add_to_cart` |
| order_id | TEXT | FK → orders | populated on `purchase` only; every order has exactly one purchase event |

## Metric definitions used across the queries

| Metric | Definition |
|---|---|
| Net revenue | Σ `(unit_price × quantity − discount_amount)` over **delivered** orders. Excludes shipping fees. |
| Gross margin | Σ `((unit_price − unit_cost) × quantity − discount_amount)` over delivered orders. |
| AOV | Net revenue ÷ delivered orders. |
| New customer (month M) | Customer whose first order of any status falls in month M. |
| Retention, month N | Share of an acquisition cohort with ≥ 1 order (any status) N calendar months after the cohort month. |
| Repeat rate | Share of customers with ≥ 2 non-cancelled orders. |
| Late delivery | `DATE(delivered_at) > estimated_delivery_date`. |
| Session conversion | Sessions with a `purchase` event ÷ all sessions. |
| Realised value at horizon H | Net revenue from delivered orders placed within H days of the customer's first delivered order, averaged over customers observable for the full H days. |
