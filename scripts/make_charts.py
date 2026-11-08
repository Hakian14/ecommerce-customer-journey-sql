"""
Render the charts referenced in README.md from the query outputs in outputs/.

    python scripts/make_charts.py

Requires: pandas, matplotlib. Charts are saved to outputs/charts/*.png.
Palette: a validated, colour-blind-safe set (blue/orange/aqua/yellow) with a
single-hue blue ramp for magnitude, recessive grid and axes, no dual axes.
"""

from __future__ import annotations

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "outputs")
CHARTS = os.path.join(OUT, "charts")

# ---- palette -------------------------------------------------------------
SURFACE, INK, INK2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
SEQ_CMAP = LinearSegmentedColormap.from_list("blue_seq", BLUE_RAMP)

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "font.family": "sans-serif", "font.size": 10,
    "axes.edgecolor": AXIS, "axes.labelcolor": INK2, "axes.titlecolor": INK, "axes.titleweight": "bold",
    "axes.titlesize": 12, "axes.titlelocation": "left",
    "xtick.color": MUTED, "ytick.color": MUTED, "xtick.labelcolor": INK2, "ytick.labelcolor": INK2,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8, "axes.axisbelow": True,
    "axes.spines.top": False, "axes.spines.right": False,
    "legend.frameon": False, "legend.fontsize": 9,
})


def _finish(fig, name: str, subtitle: str | None = None):
    if subtitle:
        fig.text(0.01, 0.005, subtitle, color=MUTED, fontsize=8, ha="left", va="bottom")
    fig.tight_layout(rect=(0, 0.03 if subtitle else 0, 1, 1))
    path = os.path.join(CHARTS, name)
    fig.savefig(path, dpi=160)
    plt.close(fig)
    print("  wrote", os.path.relpath(path, ROOT))


def monthly_revenue():
    df = pd.read_csv(os.path.join(OUT, "02_monthly_kpi_overview.csv"))
    df = df[df.order_month < "2025-11"]  # last month is incomplete (in-transit orders)
    x = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(x, df.net_revenue / 1e9, color=BLUE, linewidth=2, marker="o", markersize=4)
    for i in (df.net_revenue.idxmax(),):
        ax.annotate(f"{df.net_revenue[i] / 1e9:.2f}B", (i, df.net_revenue[i] / 1e9), textcoords="offset points",
                    xytext=(0, 8), ha="center", color=INK2, fontsize=9)
    ax.set_xticks(x[::2])
    ax.set_xticklabels(df.order_month[::2], rotation=0)
    ax.set_ylabel("Net revenue (billion VND)")
    ax.set_ylim(0)
    ax.set_title("Monthly net revenue, delivered orders")
    ax.grid(axis="x", visible=False)
    _finish(fig, "01_monthly_revenue.png", "Nov 2025 excluded: ~20% of its orders were still in transit at snapshot.")


def cohort_heatmap():
    df = pd.read_csv(os.path.join(OUT, "03_cohort_retention.csv"))
    df = df[df.months_observed >= 1]
    cols = [f"m{i}" for i in range(1, 13)]
    mat = df[cols].to_numpy(dtype=float)
    fig, ax = plt.subplots(figsize=(9, 7))
    ax.grid(False)
    im = ax.imshow(mat, cmap=SEQ_CMAP, vmin=0, vmax=np.nanmax(mat), aspect="auto")
    ax.set_xticks(range(len(cols)))
    ax.set_xticklabels([c.upper() for c in cols])
    ax.set_yticks(range(len(df)))
    ax.set_yticklabels([f"{c}  (n={n})" for c, n in zip(df.cohort, df.cohort_size)], fontsize=8.5)
    for i in range(mat.shape[0]):
        for j in range(mat.shape[1]):
            v = mat[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=7.5,
                        color="#ffffff" if v > 0.55 * np.nanmax(mat) else INK)
    ax.set_title("Cohort retention: % of cohort ordering again N months after first order")
    ax.set_xlabel("Months since first order")
    cb = fig.colorbar(im, ax=ax, fraction=0.03, pad=0.02)
    cb.set_label("% retained", color=INK2)
    cb.outline.set_visible(False)
    _finish(fig, "02_cohort_retention_heatmap.png", "Blank cells: cohort has not reached that month yet.")


def funnel_small_multiples():
    df = pd.read_csv(os.path.join(OUT, "05_conversion_funnel.csv"))
    df = df[df.channel != "ALL CHANNELS"].sort_values("session_conversion_pct", ascending=False)
    stages = ["sessions", "product_views", "add_to_carts", "checkouts", "purchases"]
    labels = ["Landing", "Product", "Cart", "Checkout", "Purchase"]
    fig, axes = plt.subplots(1, len(df), figsize=(13, 4), sharey=True)
    for ax, (_, row) in zip(axes, df.iterrows()):
        pct = [100.0 * row[s] / row["sessions"] for s in stages]
        bars = ax.bar(range(len(stages)), pct, width=0.62, color=BLUE)
        for b, v in zip(bars, pct):
            ax.text(b.get_x() + b.get_width() / 2, v + 2, f"{v:.0f}%", ha="center", fontsize=8, color=INK2)
        ax.set_xticks(range(len(stages)))
        ax.set_xticklabels(labels, fontsize=7.5)
        ax.set_title(f"{row.channel.replace('_', ' ')}  ·  {row.session_conversion_pct:.1f}% convert", fontsize=9.5)
        ax.set_ylim(0, 115)
        ax.grid(axis="x", visible=False)
    axes[0].set_ylabel("% of sessions reaching stage")
    fig.suptitle("Purchase funnel by channel", x=0.01, ha="left", fontweight="bold", fontsize=12, color=INK)
    _finish(fig, "03_funnel_by_channel.png", "Session reaches a stage if it logs at least one event of that type.")


def rfm_segments():
    df = pd.read_csv(os.path.join(OUT, "04_rfm_segmentation.csv")).iloc[::-1]
    y = np.arange(len(df))
    h = 0.38
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.barh(y + h / 2, df.pct_customers, height=h, color=BLUE, label="% of customers")
    ax.barh(y - h / 2, df.pct_revenue, height=h, color=ORANGE, label="% of revenue")
    for yi, c, r in zip(y, df.pct_customers, df.pct_revenue):
        ax.text(c + 0.6, yi + h / 2, f"{c:.0f}%", va="center", fontsize=8, color=INK2)
        ax.text(r + 0.6, yi - h / 2, f"{r:.0f}%", va="center", fontsize=8, color=INK2)
    ax.set_yticks(y)
    ax.set_yticklabels([s.split(". ", 1)[1] for s in df.segment])
    ax.set_xlabel("Share (%)")
    ax.set_title("RFM segments: customer share vs revenue share")
    ax.legend(loc="lower right")
    ax.grid(axis="y", visible=False)
    _finish(fig, "04_rfm_segments.png", "Delivered orders only. Scores = quintiles of recency, frequency and monetary value.")


def ltv_by_channel():
    df = pd.read_csv(os.path.join(OUT, "09_customer_lifetime_value.csv"))
    x = np.arange(len(df))
    w = 0.26
    fig, ax = plt.subplots(figsize=(9, 4.2))
    for k, (col, lab, color) in enumerate([("avg_value_90d", "90 days", BLUE_RAMP[1]),
                                           ("avg_value_180d", "180 days", BLUE_RAMP[3]),
                                           ("avg_value_365d", "365 days", BLUE_RAMP[5])]):
        bars = ax.bar(x + (k - 1) * w, df[col] / 1e6, width=w - 0.03, color=color, label=lab)
        if col == "avg_value_365d":
            for b, v in zip(bars, df[col] / 1e6):
                ax.text(b.get_x() + b.get_width() / 2, v + 0.08, f"{v:.1f}M", ha="center", fontsize=8, color=INK2)
    ax.set_xticks(x)
    ax.set_xticklabels([c.replace("_", " ") for c in df.acquisition_channel])
    ax.set_ylabel("Avg realised value per customer (million VND)")
    ax.set_title("Customer value by acquisition channel and tenure horizon")
    ax.legend(title="Since first order", loc="upper right")
    ax.grid(axis="x", visible=False)
    _finish(fig, "05_ltv_by_channel.png", "Each horizon only counts customers observable for the full period.")


if __name__ == "__main__":
    os.makedirs(CHARTS, exist_ok=True)
    monthly_revenue()
    cohort_heatmap()
    funnel_small_multiples()
    rfm_segments()
    ltv_by_channel()
