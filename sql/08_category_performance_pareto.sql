-- ---------------------------------------------------------------------------
-- 08_category_performance_pareto.sql
-- Category P&L view: net revenue, gross margin %, return rate, discount
-- dependence, and a Pareto cumulative-revenue share so the merchandising
-- team can see which categories make up the first 80% of revenue.
-- Return rate uses the order status (an order is returned as a whole).
-- ---------------------------------------------------------------------------

WITH line AS (
    SELECT
        p.category,
        o.order_id,
        o.status,
        oi.quantity,
        oi.unit_price * oi.quantity - oi.discount_amount                 AS net_value,
        (oi.unit_price - p.unit_cost) * oi.quantity - oi.discount_amount AS gross_margin,
        oi.discount_amount
    FROM order_items oi
    JOIN orders o   USING (order_id)
    JOIN products p USING (product_id)
    WHERE o.status IN ('delivered', 'returned')
),
cat AS (
    SELECT
        category,
        COUNT(DISTINCT order_id)                                             AS orders,
        SUM(quantity)                                                        AS units,
        SUM(CASE WHEN status = 'delivered' THEN net_value END)               AS net_revenue,
        SUM(CASE WHEN status = 'delivered' THEN gross_margin END)            AS gross_margin,
        SUM(CASE WHEN status = 'delivered' THEN discount_amount END)         AS discounts,
        COUNT(DISTINCT CASE WHEN status = 'returned' THEN order_id END)      AS returned_orders
    FROM line
    GROUP BY category
)
SELECT
    category,
    orders,
    units,
    net_revenue,
    ROUND(100.0 * net_revenue / SUM(net_revenue) OVER (), 1)                       AS revenue_share_pct,
    ROUND(100.0 * SUM(net_revenue) OVER (ORDER BY net_revenue DESC
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(net_revenue) OVER (), 1)                                           AS cumulative_revenue_pct,
    CASE WHEN 1.0 * SUM(net_revenue) OVER (ORDER BY net_revenue DESC
                                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              / SUM(net_revenue) OVER () <= 0.80 THEN 'A (top 80%)' ELSE 'B/C' END AS pareto_class,
    ROUND(100.0 * gross_margin / NULLIF(net_revenue, 0), 1)                        AS gross_margin_pct,
    ROUND(net_revenue * 1.0 / orders)                                              AS revenue_per_order,
    ROUND(100.0 * discounts / NULLIF(net_revenue + discounts, 0), 1)               AS discount_rate_pct,
    ROUND(100.0 * returned_orders / orders, 1)                                     AS return_rate_pct
FROM cat
ORDER BY net_revenue DESC;
