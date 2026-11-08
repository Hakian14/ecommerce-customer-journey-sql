-- ---------------------------------------------------------------------------
-- 05_conversion_funnel.sql
-- Session-level purchase funnel by channel from the clickstream:
--   page_view -> product_view -> add_to_cart -> checkout_start -> purchase
-- A session "reaches" a stage if it has at least one event of that type.
-- Reports step-to-step conversion and the biggest drop-off per channel.
-- Last row is the blended total.
-- ---------------------------------------------------------------------------

WITH session_stage AS (
    SELECT
        session_id,
        channel,
        MAX(CASE WHEN event_type = 'page_view'      THEN 1 ELSE 0 END) AS s1_view,
        MAX(CASE WHEN event_type = 'product_view'   THEN 1 ELSE 0 END) AS s2_product,
        MAX(CASE WHEN event_type = 'add_to_cart'    THEN 1 ELSE 0 END) AS s3_cart,
        MAX(CASE WHEN event_type = 'checkout_start' THEN 1 ELSE 0 END) AS s4_checkout,
        MAX(CASE WHEN event_type = 'purchase'       THEN 1 ELSE 0 END) AS s5_purchase
    FROM web_events
    GROUP BY session_id, channel
),
funnel AS (
    SELECT
        channel,
        COUNT(*)          AS sessions,
        SUM(s2_product)   AS product_views,
        SUM(s3_cart)      AS add_to_carts,
        SUM(s4_checkout)  AS checkouts,
        SUM(s5_purchase)  AS purchases
    FROM session_stage
    GROUP BY channel

    UNION ALL

    SELECT
        'ALL CHANNELS',
        COUNT(*), SUM(s2_product), SUM(s3_cart), SUM(s4_checkout), SUM(s5_purchase)
    FROM session_stage
)
SELECT
    channel,
    sessions,
    product_views,
    add_to_carts,
    checkouts,
    purchases,
    -- step conversion rates
    ROUND(100.0 * product_views / sessions, 1)              AS view_to_product_pct,
    ROUND(100.0 * add_to_carts  / NULLIF(product_views, 0), 1) AS product_to_cart_pct,
    ROUND(100.0 * checkouts     / NULLIF(add_to_carts, 0), 1)  AS cart_to_checkout_pct,
    ROUND(100.0 * purchases     / NULLIF(checkouts, 0), 1)     AS checkout_to_purchase_pct,
    ROUND(100.0 * purchases     / sessions, 2)              AS session_conversion_pct,
    -- where do we lose the most sessions?
    CASE
        WHEN (sessions - product_views) >= (product_views - add_to_carts)
         AND (sessions - product_views) >= (add_to_carts - checkouts)
         AND (sessions - product_views) >= (checkouts - purchases) THEN 'landing -> product'
        WHEN (product_views - add_to_carts) >= (add_to_carts - checkouts)
         AND (product_views - add_to_carts) >= (checkouts - purchases) THEN 'product -> cart'
        WHEN (add_to_carts - checkouts) >= (checkouts - purchases)     THEN 'cart -> checkout'
        ELSE 'checkout -> purchase'
    END AS biggest_drop_off
FROM funnel
ORDER BY CASE WHEN channel = 'ALL CHANNELS' THEN 1 ELSE 0 END, session_conversion_pct DESC;
