-- ---------------------------------------------------------------------------
-- 03_cohort_retention.sql
-- Classic acquisition-cohort retention triangle.
-- A customer belongs to the month of their FIRST order; retention in month N
-- = share of the cohort that placed at least one order N months later.
-- Output is one row per cohort with months 0..11 as columns, plus the
-- cohort size, so it drops straight into a heatmap.
-- ---------------------------------------------------------------------------

WITH first_order AS (
    SELECT
        customer_id,
        MIN(DATE(order_ts, 'start of month')) AS cohort_month
    FROM orders
    GROUP BY customer_id
),
activity AS (
    -- one row per (customer, active month)
    SELECT DISTINCT
        o.customer_id,
        DATE(o.order_ts, 'start of month') AS active_month
    FROM orders o
),
cohort_activity AS (
    SELECT
        f.cohort_month,
        a.customer_id,
        -- month offset between cohort month and active month
        (CAST(strftime('%Y', a.active_month) AS INTEGER) - CAST(strftime('%Y', f.cohort_month) AS INTEGER)) * 12
        + (CAST(strftime('%m', a.active_month) AS INTEGER) - CAST(strftime('%m', f.cohort_month) AS INTEGER)) AS month_offset
    FROM first_order f
    JOIN activity a USING (customer_id)
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers
    FROM first_order
    GROUP BY cohort_month
),
retention AS (
    SELECT
        ca.cohort_month,
        ca.month_offset,
        COUNT(DISTINCT ca.customer_id) AS retained
    FROM cohort_activity ca
    GROUP BY ca.cohort_month, ca.month_offset
),
-- how many months of data does each cohort actually have? (to avoid
-- reading an empty cell as 0% retention)
max_offset AS (
    SELECT
        cohort_month,
        (CAST(strftime('%Y', (SELECT MAX(DATE(order_ts, 'start of month')) FROM orders)) AS INTEGER)
           - CAST(strftime('%Y', cohort_month) AS INTEGER)) * 12
        + (CAST(strftime('%m', (SELECT MAX(DATE(order_ts, 'start of month')) FROM orders)) AS INTEGER)
           - CAST(strftime('%m', cohort_month) AS INTEGER)) AS months_observed
    FROM cohort_size
)
SELECT
    strftime('%Y-%m', cs.cohort_month) AS cohort,
    cs.customers                       AS cohort_size,
    mo.months_observed,
    -- retention % by month offset; NULL where the cohort has not reached that month yet
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 1  THEN r.retained END) / cs.customers, 1) AS m1,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 2  THEN r.retained END) / cs.customers, 1) AS m2,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 3  THEN r.retained END) / cs.customers, 1) AS m3,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 4  THEN r.retained END) / cs.customers, 1) AS m4,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 5  THEN r.retained END) / cs.customers, 1) AS m5,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 6  THEN r.retained END) / cs.customers, 1) AS m6,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 7  THEN r.retained END) / cs.customers, 1) AS m7,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 8  THEN r.retained END) / cs.customers, 1) AS m8,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 9  THEN r.retained END) / cs.customers, 1) AS m9,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 10 THEN r.retained END) / cs.customers, 1) AS m10,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 11 THEN r.retained END) / cs.customers, 1) AS m11,
    ROUND(100.0 * MAX(CASE WHEN r.month_offset = 12 THEN r.retained END) / cs.customers, 1) AS m12
FROM cohort_size cs
JOIN max_offset mo USING (cohort_month)
LEFT JOIN retention r USING (cohort_month)
GROUP BY cs.cohort_month, cs.customers, mo.months_observed
ORDER BY cs.cohort_month;
