-- ---------------------------------------------------------------------------
-- 09_customer_lifetime_value.sql
-- Realised customer value at fixed tenure horizons (90 / 180 / 365 days
-- after first order), by acquisition channel. Only customers who have
-- been observable for the full horizon are counted at that horizon, so
-- the numbers are comparable across channels and not biased by recent
-- cohorts. This is the table that answers "which channel is worth paying
-- more to acquire from?".
-- ---------------------------------------------------------------------------

WITH order_value AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.order_ts,
        SUM(oi.unit_price * oi.quantity - oi.discount_amount) AS net_value
    FROM orders o
    JOIN order_items oi USING (order_id)
    WHERE o.status = 'delivered'
    GROUP BY o.order_id
),
first_order AS (
    SELECT customer_id, MIN(order_ts) AS first_ts
    FROM order_value
    GROUP BY customer_id
),
snapshot AS (
    SELECT MAX(order_ts) AS as_of FROM orders
),
tenure_value AS (
    SELECT
        f.customer_id,
        c.acquisition_channel,
        julianday((SELECT as_of FROM snapshot)) - julianday(f.first_ts)          AS days_observed,
        SUM(CASE WHEN julianday(ov.order_ts) - julianday(f.first_ts) <= 90  THEN ov.net_value ELSE 0 END) AS value_90d,
        SUM(CASE WHEN julianday(ov.order_ts) - julianday(f.first_ts) <= 180 THEN ov.net_value ELSE 0 END) AS value_180d,
        SUM(CASE WHEN julianday(ov.order_ts) - julianday(f.first_ts) <= 365 THEN ov.net_value ELSE 0 END) AS value_365d,
        SUM(ov.net_value)                                                        AS value_to_date,
        COUNT(*)                                                                 AS orders_to_date
    FROM first_order f
    JOIN customers c   USING (customer_id)
    JOIN order_value ov USING (customer_id)
    GROUP BY f.customer_id, c.acquisition_channel, f.first_ts
)
SELECT
    acquisition_channel,
    COUNT(*)                                                                       AS customers,
    -- average realised value, restricted to customers observable for the horizon
    ROUND(AVG(CASE WHEN days_observed >= 90  THEN value_90d  END))                 AS avg_value_90d,
    ROUND(AVG(CASE WHEN days_observed >= 180 THEN value_180d END))                 AS avg_value_180d,
    ROUND(AVG(CASE WHEN days_observed >= 365 THEN value_365d END))                 AS avg_value_365d,
    SUM(CASE WHEN days_observed >= 365 THEN 1 ELSE 0 END)                          AS customers_with_365d,
    ROUND(AVG(value_to_date))                                                      AS avg_value_to_date,
    ROUND(AVG(orders_to_date), 2)                                                  AS avg_orders_to_date,
    -- how much of 1-year value is generated after the first 90 days?
    ROUND(100.0 * (AVG(CASE WHEN days_observed >= 365 THEN value_365d END)
                   - AVG(CASE WHEN days_observed >= 365 THEN value_90d END))
          / NULLIF(AVG(CASE WHEN days_observed >= 365 THEN value_365d END), 0), 1) AS pct_value_after_90d
FROM tenure_value
GROUP BY acquisition_channel
ORDER BY avg_value_365d DESC;
