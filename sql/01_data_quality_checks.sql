-- ---------------------------------------------------------------------------
-- 01_data_quality_checks.sql
-- Before analysing anything: can the data be trusted?
-- Each row is one check; `issues` should be 0 for a clean load.
-- This mirrors the validation layer I would put in front of any dashboard.
-- ---------------------------------------------------------------------------

WITH order_totals AS (
    SELECT
        oi.order_id,
        SUM(oi.unit_price * oi.quantity - oi.discount_amount) AS items_net
    FROM order_items oi
    GROUP BY oi.order_id
)

-- 1. Referential integrity --------------------------------------------------
SELECT 'orders.customer_id not in customers' AS check_name,
       COUNT(*) AS issues
FROM orders o LEFT JOIN customers c USING (customer_id)
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'order_items.order_id not in orders', COUNT(*)
FROM order_items oi LEFT JOIN orders o USING (order_id)
WHERE o.order_id IS NULL

UNION ALL
SELECT 'order_items.product_id not in products', COUNT(*)
FROM order_items oi LEFT JOIN products p USING (product_id)
WHERE p.product_id IS NULL

UNION ALL
SELECT 'orders without any order_items', COUNT(*)
FROM orders o LEFT JOIN order_items oi USING (order_id)
WHERE oi.order_id IS NULL

UNION ALL
SELECT 'orders without a payment', COUNT(*)
FROM orders o LEFT JOIN payments p USING (order_id)
WHERE p.payment_id IS NULL

-- 2. Business-rule consistency ----------------------------------------------
UNION ALL
SELECT 'payment amount != items net + shipping', COUNT(*)
FROM payments p
JOIN order_totals t USING (order_id)
WHERE p.amount <> t.items_net + p.shipping_fee

UNION ALL
SELECT 'delivered orders missing delivered_at', COUNT(*)
FROM orders
WHERE status IN ('delivered', 'returned') AND delivered_at IS NULL

UNION ALL
SELECT 'non-delivered orders with delivered_at', COUNT(*)
FROM orders
WHERE status IN ('cancelled', 'in_transit') AND delivered_at IS NOT NULL

UNION ALL
SELECT 'orders placed before customer signup', COUNT(*)
FROM orders o JOIN customers c USING (customer_id)
WHERE DATE(o.order_ts) < c.signup_date

UNION ALL
SELECT 'delivered before ordered', COUNT(*)
FROM orders
WHERE delivered_at IS NOT NULL AND delivered_at < order_ts

UNION ALL
SELECT 'discount larger than line value', COUNT(*)
FROM order_items
WHERE discount_amount > unit_price * quantity

UNION ALL
SELECT 'review score outside 1..5', COUNT(*)
FROM reviews WHERE review_score NOT BETWEEN 1 AND 5

-- 3. Uniqueness --------------------------------------------------------------
UNION ALL
SELECT 'duplicate order_id', COUNT(*) FROM (
    SELECT order_id FROM orders GROUP BY order_id HAVING COUNT(*) > 1
)

UNION ALL
SELECT 'orders with more than one payment', COUNT(*) FROM (
    SELECT order_id FROM payments GROUP BY order_id HAVING COUNT(*) > 1
)

-- 4. Clickstream sanity ------------------------------------------------------
UNION ALL
SELECT 'purchase events without matching order', COUNT(*)
FROM web_events e LEFT JOIN orders o USING (order_id)
WHERE e.event_type = 'purchase' AND o.order_id IS NULL

UNION ALL
SELECT 'orders without a purchase event', COUNT(*)
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM web_events e WHERE e.order_id = o.order_id AND e.event_type = 'purchase')

UNION ALL
SELECT 'unknown event_type values', COUNT(*)
FROM web_events
WHERE event_type NOT IN ('page_view', 'product_view', 'add_to_cart', 'checkout_start', 'purchase');
