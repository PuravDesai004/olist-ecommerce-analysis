-- Olist 2.0 Phase 1B: run after importing the nine source CSVs.
-- CSV timestamps are typed during COPY; malformed timestamp text causes COPY
-- to fail. These queries check imported counts, nulls, keys, relationships,
-- observed event-order anomalies, and item/payment reconciliation.

-- 1. Imported row counts against the original project README / source counts.
SELECT 'customers' AS table_name, COUNT(*) AS actual_rows, 99441 AS expected_rows FROM public.customers
UNION ALL SELECT 'geolocation', COUNT(*), 1000163 FROM public.geolocation
UNION ALL SELECT 'order_items', COUNT(*), 112650 FROM public.order_items
UNION ALL SELECT 'order_payments', COUNT(*), 103886 FROM public.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*), 99224 FROM public.order_reviews
UNION ALL SELECT 'orders', COUNT(*), 99441 FROM public.orders
UNION ALL SELECT 'products', COUNT(*), 32951 FROM public.products
UNION ALL SELECT 'sellers', COUNT(*), 3095 FROM public.sellers
UNION ALL SELECT 'product_category_name_translation', COUNT(*), 71 FROM public.product_category_name_translation
ORDER BY table_name;

-- 2. Null counts for every original CSV column. Comment and product attributes
-- have expected nulls; these results are diagnostic, not automatic failures.
SELECT 'customers' AS table_name, 'customer_id' AS column_name, COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_rows FROM public.customers
UNION ALL SELECT 'customers', 'customer_unique_id', COUNT(*) FILTER (WHERE customer_unique_id IS NULL) FROM public.customers
UNION ALL SELECT 'customers', 'customer_zip_code_prefix', COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) FROM public.customers
UNION ALL SELECT 'customers', 'customer_city', COUNT(*) FILTER (WHERE customer_city IS NULL) FROM public.customers
UNION ALL SELECT 'customers', 'customer_state', COUNT(*) FILTER (WHERE customer_state IS NULL) FROM public.customers
UNION ALL SELECT 'geolocation', 'geolocation_zip_code_prefix', COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) FROM public.geolocation
UNION ALL SELECT 'geolocation', 'geolocation_lat', COUNT(*) FILTER (WHERE geolocation_lat IS NULL) FROM public.geolocation
UNION ALL SELECT 'geolocation', 'geolocation_lng', COUNT(*) FILTER (WHERE geolocation_lng IS NULL) FROM public.geolocation
UNION ALL SELECT 'geolocation', 'geolocation_city', COUNT(*) FILTER (WHERE geolocation_city IS NULL) FROM public.geolocation
UNION ALL SELECT 'geolocation', 'geolocation_state', COUNT(*) FILTER (WHERE geolocation_state IS NULL) FROM public.geolocation
UNION ALL SELECT 'order_items', 'order_id', COUNT(*) FILTER (WHERE order_id IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'order_item_id', COUNT(*) FILTER (WHERE order_item_id IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'product_id', COUNT(*) FILTER (WHERE product_id IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'seller_id', COUNT(*) FILTER (WHERE seller_id IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'shipping_limit_date', COUNT(*) FILTER (WHERE shipping_limit_date IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'price', COUNT(*) FILTER (WHERE price IS NULL) FROM public.order_items
UNION ALL SELECT 'order_items', 'freight_value', COUNT(*) FILTER (WHERE freight_value IS NULL) FROM public.order_items
UNION ALL SELECT 'order_payments', 'order_id', COUNT(*) FILTER (WHERE order_id IS NULL) FROM public.order_payments
UNION ALL SELECT 'order_payments', 'payment_sequential', COUNT(*) FILTER (WHERE payment_sequential IS NULL) FROM public.order_payments
UNION ALL SELECT 'order_payments', 'payment_type', COUNT(*) FILTER (WHERE payment_type IS NULL) FROM public.order_payments
UNION ALL SELECT 'order_payments', 'payment_installments', COUNT(*) FILTER (WHERE payment_installments IS NULL) FROM public.order_payments
UNION ALL SELECT 'order_payments', 'payment_value', COUNT(*) FILTER (WHERE payment_value IS NULL) FROM public.order_payments
UNION ALL SELECT 'order_reviews', 'review_id', COUNT(*) FILTER (WHERE review_id IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'order_id', COUNT(*) FILTER (WHERE order_id IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'review_score', COUNT(*) FILTER (WHERE review_score IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'review_comment_title', COUNT(*) FILTER (WHERE review_comment_title IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'review_comment_message', COUNT(*) FILTER (WHERE review_comment_message IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'review_creation_date', COUNT(*) FILTER (WHERE review_creation_date IS NULL) FROM public.order_reviews
UNION ALL SELECT 'order_reviews', 'review_answer_timestamp', COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) FROM public.order_reviews
UNION ALL SELECT 'orders', 'order_id', COUNT(*) FILTER (WHERE order_id IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'customer_id', COUNT(*) FILTER (WHERE customer_id IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_status', COUNT(*) FILTER (WHERE order_status IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_purchase_timestamp', COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_approved_at', COUNT(*) FILTER (WHERE order_approved_at IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_delivered_carrier_date', COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_delivered_customer_date', COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) FROM public.orders
UNION ALL SELECT 'orders', 'order_estimated_delivery_date', COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) FROM public.orders
UNION ALL SELECT 'products', 'product_id', COUNT(*) FILTER (WHERE product_id IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_category_name', COUNT(*) FILTER (WHERE product_category_name IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_name_lenght', COUNT(*) FILTER (WHERE product_name_lenght IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_description_lenght', COUNT(*) FILTER (WHERE product_description_lenght IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_photos_qty', COUNT(*) FILTER (WHERE product_photos_qty IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_weight_g', COUNT(*) FILTER (WHERE product_weight_g IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_length_cm', COUNT(*) FILTER (WHERE product_length_cm IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_height_cm', COUNT(*) FILTER (WHERE product_height_cm IS NULL) FROM public.products
UNION ALL SELECT 'products', 'product_width_cm', COUNT(*) FILTER (WHERE product_width_cm IS NULL) FROM public.products
UNION ALL SELECT 'sellers', 'seller_id', COUNT(*) FILTER (WHERE seller_id IS NULL) FROM public.sellers
UNION ALL SELECT 'sellers', 'seller_zip_code_prefix', COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) FROM public.sellers
UNION ALL SELECT 'sellers', 'seller_city', COUNT(*) FILTER (WHERE seller_city IS NULL) FROM public.sellers
UNION ALL SELECT 'sellers', 'seller_state', COUNT(*) FILTER (WHERE seller_state IS NULL) FROM public.sellers
UNION ALL SELECT 'product_category_name_translation', 'product_category_name', COUNT(*) FILTER (WHERE product_category_name IS NULL) FROM public.product_category_name_translation
UNION ALL SELECT 'product_category_name_translation', 'product_category_name_english', COUNT(*) FILTER (WHERE product_category_name_english IS NULL) FROM public.product_category_name_translation
ORDER BY table_name, column_name;

-- 3. Duplicate rows beyond the first for candidate keys. The source allows
-- customer_unique_id, review_id, and order_reviews.order_id to repeat.
SELECT 'customers.customer_id' AS key_name, COALESCE(SUM(n - 1), 0) AS duplicate_rows
FROM (SELECT COUNT(*) AS n FROM public.customers GROUP BY customer_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'orders.order_id', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.orders GROUP BY order_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'order_items(order_id, order_item_id)', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'order_payments(order_id, payment_sequential)', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'products.product_id', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.products GROUP BY product_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'sellers.seller_id', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.sellers GROUP BY seller_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'product_category_name_translation.product_category_name', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.product_category_name_translation GROUP BY product_category_name HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'customers.customer_unique_id (repeat values are expected)', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.customers GROUP BY customer_unique_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'order_reviews.review_id (repeat values are retained)', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.order_reviews GROUP BY review_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'order_reviews.order_id (multiple reviews are retained)', COALESCE(SUM(n - 1), 0)
FROM (SELECT COUNT(*) AS n FROM public.order_reviews GROUP BY order_id HAVING COUNT(*) > 1) AS d
UNION ALL SELECT 'geolocation exact duplicate source rows', COALESCE(SUM(n - 1), 0)
FROM (
    SELECT COUNT(*) AS n
    FROM public.geolocation
    GROUP BY geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
             geolocation_city, geolocation_state
    HAVING COUNT(*) > 1
) AS d
ORDER BY key_name;

-- 4. Referential-integrity checks. Product category translation and ZIP-code
-- geolocation coverage are intentionally diagnostic rather than constraints.
SELECT 'orders.customer_id -> customers.customer_id' AS relationship, COUNT(*) AS orphan_rows
FROM public.orders o LEFT JOIN public.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL SELECT 'order_items.order_id -> orders.order_id', COUNT(*)
FROM public.order_items i LEFT JOIN public.orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'order_items.product_id -> products.product_id', COUNT(*)
FROM public.order_items i LEFT JOIN public.products p ON p.product_id = i.product_id
WHERE p.product_id IS NULL
UNION ALL SELECT 'order_items.seller_id -> sellers.seller_id', COUNT(*)
FROM public.order_items i LEFT JOIN public.sellers s ON s.seller_id = i.seller_id
WHERE s.seller_id IS NULL
UNION ALL SELECT 'order_payments.order_id -> orders.order_id', COUNT(*)
FROM public.order_payments p LEFT JOIN public.orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'order_reviews.order_id -> orders.order_id', COUNT(*)
FROM public.order_reviews r LEFT JOIN public.orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'products category without translation (informational)', COUNT(*)
FROM public.products p
LEFT JOIN public.product_category_name_translation t
  ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
UNION ALL SELECT 'customer ZIP prefix without geolocation match (distinct prefixes)', COUNT(*)
FROM (
    SELECT DISTINCT c.customer_zip_code_prefix
    FROM public.customers c
    LEFT JOIN public.geolocation g
      ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
    WHERE c.customer_zip_code_prefix IS NOT NULL AND g.geolocation_zip_code_prefix IS NULL
) AS missing_customer_zip
UNION ALL SELECT 'seller ZIP prefix without geolocation match (distinct prefixes)', COUNT(*)
FROM (
    SELECT DISTINCT s.seller_zip_code_prefix
    FROM public.sellers s
    LEFT JOIN public.geolocation g
      ON g.geolocation_zip_code_prefix = s.seller_zip_code_prefix
    WHERE s.seller_zip_code_prefix IS NOT NULL AND g.geolocation_zip_code_prefix IS NULL
) AS missing_seller_zip
ORDER BY relationship;

-- 5. Timestamp order diagnostics. A parsed timestamp can still be out of
-- sequence; the source contains some such rows, so these are not constraints.
SELECT 'purchase after approval' AS check_name, COUNT(*) AS anomalous_rows
FROM public.orders
WHERE order_purchase_timestamp > order_approved_at
UNION ALL SELECT 'approval after carrier handoff', COUNT(*)
FROM public.orders
WHERE order_approved_at > order_delivered_carrier_date
UNION ALL SELECT 'carrier handoff after customer delivery', COUNT(*)
FROM public.orders
WHERE order_delivered_carrier_date > order_delivered_customer_date
UNION ALL SELECT 'review creation after review answer', COUNT(*)
FROM public.order_reviews
WHERE review_creation_date > review_answer_timestamp
ORDER BY check_name;

-- 6. Per-order financial reconciliation in BRL. Differences over BRL 0.01
-- are diagnostics; discounts/vouchers are not represented in the source files.
WITH item_totals AS (
    SELECT order_id, SUM(price + freight_value) AS item_and_freight_total
    FROM public.order_items
    GROUP BY order_id
), payment_totals AS (
    SELECT order_id, SUM(payment_value) AS payment_total
    FROM public.order_payments
    GROUP BY order_id
), compared AS (
    SELECT i.order_id, i.item_and_freight_total, p.payment_total
    FROM item_totals i
    FULL OUTER JOIN payment_totals p USING (order_id)
)
SELECT
    COUNT(*) FILTER (WHERE item_and_freight_total IS NOT NULL AND payment_total IS NOT NULL) AS compared_orders,
    COUNT(*) FILTER (WHERE item_and_freight_total IS NOT NULL AND payment_total IS NULL) AS item_only_orders,
    COUNT(*) FILTER (WHERE item_and_freight_total IS NULL AND payment_total IS NOT NULL) AS payment_only_orders,
    COUNT(*) FILTER (
        WHERE item_and_freight_total IS NOT NULL AND payment_total IS NOT NULL
          AND ABS(payment_total - item_and_freight_total) > 0.01
    ) AS orders_over_01_difference,
    COALESCE(ROUND(SUM(ABS(payment_total - item_and_freight_total)) FILTER (
        WHERE item_and_freight_total IS NOT NULL AND payment_total IS NOT NULL
          AND ABS(payment_total - item_and_freight_total) > 0.01
    ), 2), 0) AS total_absolute_difference_brl
FROM compared;
