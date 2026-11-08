-- ---------------------------------------------------------------------------
-- 02_monthly_kpi_overview.sql
-- The executive view: orders, net revenue, AOV, new vs returning customers,
-- and month-over-month growth. Revenue counts delivered orders only
-- (cancelled / returned / in-transit orders are excluded from revenue
-- but still counted in `orders_placed`).
-- ---------------------------------------------------------------------------

WITH order_value AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.status,
        strftime('%Y-%m', o.order_ts)                              AS order_month,
        SUM(oi.unit_price * oi.quantity - oi.discount_amount)      AS net_value,
        SUM(oi.discount_amount)                                    AS discount,
        SUM((oi.unit_price - p.unit_cost) * oi.quantity
            - oi.discount_amount)                                  AS gross_margin
    FROM orders o
    JOIN order_items oi USING (order_id)
    JOIN products p     USING (product_id)
    GROUP BY o.order_id
),
first_order AS (
    SELECT customer_id, strftime('%Y-%m', MIN(order_ts)) AS first_month
    FROM orders
    GROUP BY customer_id
),
monthly AS (
    SELECT
        ov.order_month,
        COUNT(*)                                                           AS orders_placed,
        SUM(CASE WHEN ov.status = 'delivered' THEN 1 ELSE 0 END)           AS orders_delivered,
        SUM(CASE WHEN ov.status = 'delivered' THEN ov.net_value END)       AS net_revenue,
        SUM(CASE WHEN ov.status = 'delivered' THEN ov.gross_margin END)    AS gross_margin,
        SUM(CASE WHEN ov.status = 'delivered' THEN ov.discount END)        AS discounts_given,
        COUNT(DISTINCT ov.customer_id)                                     AS active_customers,
        COUNT(DISTINCT CASE WHEN fo.first_month = ov.order_month
                            THEN ov.customer_id END)                       AS new_customers
    FROM order_value ov
    JOIN first_order fo USING (customer_id)
    GROUP BY ov.order_month
)
SELECT
    order_month,
    orders_placed,
    orders_delivered,
    ROUND(100.0 * (orders_placed - orders_delivered) / orders_placed, 1)  AS pct_not_delivered,
    net_revenue,
    ROUND(net_revenue * 1.0 / NULLIF(orders_delivered, 0))                AS aov,
    ROUND(100.0 * gross_margin / NULLIF(net_revenue, 0), 1)               AS gross_margin_pct,
    ROUND(100.0 * discounts_given / NULLIF(net_revenue + discounts_given, 0), 1) AS discount_rate_pct,
    active_customers,
    new_customers,
    active_customers - new_customers                                      AS returning_customers,
    ROUND(100.0 * (active_customers - new_customers) / active_customers, 1) AS pct_returning,
    ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY order_month))
          / NULLIF(LAG(net_revenue) OVER (ORDER BY order_month), 0), 1)     AS revenue_mom_pct,
    ROUND(100.0 * (net_revenue - LAG(net_revenue, 12) OVER (ORDER BY order_month))
          / NULLIF(LAG(net_revenue, 12) OVER (ORDER BY order_month), 0), 1) AS revenue_yoy_pct,
    SUM(net_revenue) OVER (ORDER BY order_month
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_revenue
FROM monthly
ORDER BY order_month;
