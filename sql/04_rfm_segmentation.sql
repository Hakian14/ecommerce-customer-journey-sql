-- ---------------------------------------------------------------------------
-- 04_rfm_segmentation.sql
-- Recency / Frequency / Monetary scoring with NTILE, then a rule-based
-- mapping into marketing segments. The output is one row per segment with
-- size, revenue share and average metrics - the table a CRM team would use
-- to size campaigns. (Change the final SELECT to `SELECT * FROM scored`
-- to get the customer-level list for activation.)
-- Only delivered orders count toward frequency and monetary value.
-- ---------------------------------------------------------------------------

WITH snapshot AS (
    SELECT DATE(MAX(order_ts)) AS as_of FROM orders
),
customer_metrics AS (
    SELECT
        o.customer_id,
        CAST(julianday((SELECT as_of FROM snapshot)) - julianday(MAX(o.order_ts)) AS INTEGER) AS recency_days,
        COUNT(DISTINCT o.order_id)                                                            AS frequency,
        SUM(oi.unit_price * oi.quantity - oi.discount_amount)                                AS monetary
    FROM orders o
    JOIN order_items oi USING (order_id)
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
),
scored AS (
    SELECT
        cm.*,
        -- recency: fewer days = better = higher score, hence DESC
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM customer_metrics cm
),
segmented AS (
    SELECT
        s.*,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
            WHEN r_score >= 3 AND f_score >= 4                  THEN '2. Loyal customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN '3. New / promising'
            WHEN r_score >= 3 AND f_score = 3                   THEN '4. Potential loyalists'
            WHEN r_score = 3 AND f_score <= 2                   THEN '5. Need attention'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN '6. At risk (high value)'
            WHEN r_score <= 2 AND f_score >= 3                  THEN '7. At risk'
            WHEN r_score = 2                                    THEN '8. Hibernating'
            ELSE                                                     '9. Lost'
        END AS segment
    FROM scored s
),
totals AS (
    SELECT COUNT(*) AS n_customers, SUM(monetary) AS total_revenue FROM segmented
)
SELECT
    sg.segment,
    COUNT(*)                                                             AS customers,
    ROUND(100.0 * COUNT(*) / t.n_customers, 1)                           AS pct_customers,
    SUM(sg.monetary)                                                     AS revenue,
    ROUND(100.0 * SUM(sg.monetary) / t.total_revenue, 1)                 AS pct_revenue,
    ROUND(AVG(sg.recency_days))                                          AS avg_recency_days,
    ROUND(AVG(sg.frequency), 2)                                          AS avg_orders,
    ROUND(AVG(sg.monetary))                                              AS avg_revenue_per_customer,
    -- revenue concentration: how much more valuable than the average customer
    ROUND((SUM(sg.monetary) * 1.0 / COUNT(*)) / (t.total_revenue * 1.0 / t.n_customers), 2) AS value_index
FROM segmented sg
CROSS JOIN totals t
GROUP BY sg.segment, t.n_customers, t.total_revenue
ORDER BY sg.segment;
