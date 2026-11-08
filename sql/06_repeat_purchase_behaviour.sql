-- ---------------------------------------------------------------------------
-- 06_repeat_purchase_behaviour.sql
-- What separates one-time buyers from repeaters? Grouped by acquisition
-- channel: repeat rate, time to second order (median via window ranking),
-- average gap between orders, and the share of repeaters whose second
-- order lands within 30 / 90 days - the windows a CRM team would use to
-- time win-back campaigns.
-- ---------------------------------------------------------------------------

WITH ranked AS (
    SELECT
        o.customer_id,
        o.order_ts,
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.order_ts)         AS order_no,
        LAG(o.order_ts) OVER (PARTITION BY o.customer_id ORDER BY o.order_ts)      AS prev_order_ts
    FROM orders o
    WHERE o.status <> 'cancelled'
),
gaps AS (
    SELECT
        customer_id,
        order_no,
        julianday(order_ts) - julianday(prev_order_ts) AS days_since_prev
    FROM ranked
    WHERE prev_order_ts IS NOT NULL
),
per_customer AS (
    SELECT
        c.customer_id,
        c.acquisition_channel,
        MAX(r.order_no)                                              AS n_orders,
        MIN(CASE WHEN g.order_no = 2 THEN g.days_since_prev END)     AS days_to_second_order,
        AVG(g.days_since_prev)                                       AS avg_gap_days
    FROM customers c
    JOIN ranked r USING (customer_id)
    LEFT JOIN gaps g USING (customer_id)
    GROUP BY c.customer_id, c.acquisition_channel
),
-- median of days_to_second_order per channel, computed with window functions
second_order_ranked AS (
    SELECT
        acquisition_channel,
        days_to_second_order,
        ROW_NUMBER() OVER (PARTITION BY acquisition_channel ORDER BY days_to_second_order) AS rn,
        COUNT(*)     OVER (PARTITION BY acquisition_channel)                               AS cnt
    FROM per_customer
    WHERE days_to_second_order IS NOT NULL
),
median_second AS (
    SELECT acquisition_channel, AVG(days_to_second_order) AS median_days_to_second_order
    FROM second_order_ranked
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY acquisition_channel
)
SELECT
    pc.acquisition_channel,
    COUNT(*)                                                                    AS customers,
    SUM(CASE WHEN pc.n_orders >= 2 THEN 1 ELSE 0 END)                           AS repeaters,
    ROUND(100.0 * SUM(CASE WHEN pc.n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct,
    ROUND(AVG(pc.n_orders), 2)                                                  AS avg_orders_per_customer,
    ROUND(ms.median_days_to_second_order)                                       AS median_days_to_2nd_order,
    ROUND(AVG(pc.avg_gap_days))                                                 AS avg_gap_between_orders,
    ROUND(100.0 * SUM(CASE WHEN pc.days_to_second_order <= 30 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN pc.n_orders >= 2 THEN 1 ELSE 0 END), 0), 1)    AS pct_repeat_within_30d,
    ROUND(100.0 * SUM(CASE WHEN pc.days_to_second_order <= 90 THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN pc.n_orders >= 2 THEN 1 ELSE 0 END), 0), 1)    AS pct_repeat_within_90d
FROM per_customer pc
LEFT JOIN median_second ms USING (acquisition_channel)
GROUP BY pc.acquisition_channel, ms.median_days_to_second_order
ORDER BY repeat_rate_pct DESC;
