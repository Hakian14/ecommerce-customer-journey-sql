-- ---------------------------------------------------------------------------
-- 07_delivery_experience_and_reviews.sql
-- Does a late first delivery cost us the customer?
-- Part A (per region): late-delivery rate, average review score for on-time
--   vs late deliveries, and the review-score gap.
-- Part B (the business question): repeat rate of customers whose FIRST
--   delivered order arrived late vs on time. If the gap is large, fixing
--   logistics is a retention lever, not just an ops metric.
-- Both parts are returned in one result set with a `section` column.
-- ---------------------------------------------------------------------------

WITH delivered AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.region,
        o.order_ts,
        CASE WHEN DATE(o.delivered_at) > o.estimated_delivery_date THEN 1 ELSE 0 END   AS is_late,
        MAX(julianday(DATE(o.delivered_at)) - julianday(o.estimated_delivery_date), 0) AS days_late,
        r.review_score
    FROM orders o
    JOIN customers c USING (customer_id)
    LEFT JOIN reviews r USING (order_id)
    WHERE o.status IN ('delivered', 'returned')
),
-- Part A ---------------------------------------------------------------------
by_region AS (
    SELECT
        'A. by region'                                                       AS section,
        region                                                               AS dimension,
        COUNT(*)                                                             AS delivered_orders,
        ROUND(100.0 * SUM(is_late) / COUNT(*), 1)                            AS late_rate_pct,
        ROUND(AVG(CASE WHEN is_late = 1 THEN days_late END), 1)              AS avg_days_late_when_late,
        ROUND(AVG(CASE WHEN is_late = 0 THEN review_score END), 2)           AS avg_score_on_time,
        ROUND(AVG(CASE WHEN is_late = 1 THEN review_score END), 2)           AS avg_score_late,
        ROUND(AVG(CASE WHEN is_late = 0 THEN review_score END)
              - AVG(CASE WHEN is_late = 1 THEN review_score END), 2)         AS score_gap,
        NULL                                                                 AS repeat_rate_pct
    FROM delivered
    GROUP BY region
),
-- Part B ---------------------------------------------------------------------
first_delivered AS (
    SELECT
        customer_id,
        is_late AS first_order_late,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts) AS rn
    FROM delivered
),
customer_orders AS (
    SELECT customer_id, COUNT(*) AS n_orders
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY customer_id
),
first_vs_repeat AS (
    SELECT
        'B. first delivery experience'                                        AS section,
        CASE WHEN fd.first_order_late = 1 THEN 'first order LATE' ELSE 'first order on time' END AS dimension,
        COUNT(*)                                                              AS delivered_orders,   -- here: customers
        NULL                                                                  AS late_rate_pct,
        NULL                                                                  AS avg_days_late_when_late,
        NULL                                                                  AS avg_score_on_time,
        NULL                                                                  AS avg_score_late,
        NULL                                                                  AS score_gap,
        ROUND(100.0 * SUM(CASE WHEN co.n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct
    FROM first_delivered fd
    JOIN customer_orders co USING (customer_id)
    WHERE fd.rn = 1
    GROUP BY fd.first_order_late
)
SELECT * FROM by_region
UNION ALL
SELECT * FROM first_vs_repeat
ORDER BY section, dimension;
