-- Olist 2.0 Phase 1D: read-only business metric and grain validation.
-- Run after 01_create_tables.sql and 02_import_data.sql.
--
-- Grain and filters:
--   orders: one row per order_id; order-status counts include every order.
--   order_items: one row per (order_id, order_item_id); item sales sum price
--     only, and freight is reported separately, for all order statuses.
--   order_payments: one row per (order_id, payment_sequential); payment totals
--     include all payment rows/statuses. AOV divides by distinct order_ids with
--     at least one payment row.
--   order_reviews: one source row per review record; average score is per row.
--   customers: one row per customer_id. Returning people are grouped by
--     customer_unique_id and have more than one distinct order_id.
--
-- Child tables are aggregated to order_id before joining, avoiding the
-- items x payments x reviews fanout that inflates sums in raw multiway joins.

BEGIN TRANSACTION READ ONLY;

-- 1. Distinct row grains and key populations.
SELECT 'orders' AS dataset, COUNT(*) AS rows, COUNT(DISTINCT order_id) AS grain_keys
FROM public.orders
UNION ALL SELECT 'customers', COUNT(*), COUNT(DISTINCT customer_id) FROM public.customers
UNION ALL SELECT 'customer_unique_id people', COUNT(DISTINCT customer_unique_id), COUNT(DISTINCT customer_unique_id) FROM public.customers
UNION ALL SELECT 'order_items', COUNT(*), COUNT(DISTINCT (order_id, order_item_id)) FROM public.order_items
UNION ALL SELECT 'order_payments', COUNT(*), COUNT(DISTINCT (order_id, payment_sequential)) FROM public.order_payments
-- Reviews have no declared unique key; distinct full source rows are only a diagnostic.
UNION ALL SELECT 'order_reviews exact source rows', COUNT(*), COUNT(DISTINCT (
    review_id, order_id, review_score, review_comment_title, review_comment_message,
    review_creation_date, review_answer_timestamp
)) FROM public.order_reviews
ORDER BY dataset;

-- 2. Order status populations; denominator is every row in public.orders.
SELECT o.order_status,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM public.orders), 0), 2) AS pct_all_orders
FROM public.orders AS o
GROUP BY o.order_status
ORDER BY o.order_status;

-- 3. Independent KPI results. Each measure is aggregated at its source grain.
WITH valid_delivered AS (
    SELECT order_id,
           order_purchase_timestamp,
           order_delivered_customer_date,
           order_estimated_delivery_date
    FROM public.orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
), person_order_counts AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM public.orders AS o
    JOIN public.customers AS c ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
), kpis AS (
    SELECT 'Total orders' AS metric,
           COUNT(*)::NUMERIC AS value,
           'All rows in orders; all order statuses; grain: order_id.' AS population
    FROM public.orders
    UNION ALL
    SELECT 'Delivered orders', COUNT(*)::NUMERIC,
           'orders.order_status = delivered; grain: order_id.'
    FROM public.orders WHERE order_status = 'delivered'
    UNION ALL
    SELECT 'Total item sales (BRL)', ROUND(SUM(price), 2),
           'SUM(order_items.price); all item rows/statuses; freight excluded.'
    FROM public.order_items
    UNION ALL
    SELECT 'Total freight (BRL)', ROUND(SUM(freight_value), 2),
           'SUM(order_items.freight_value); all item rows/statuses.'
    FROM public.order_items
    UNION ALL
    SELECT 'Item sales plus freight (BRL)', ROUND(SUM(price + freight_value), 2),
           'SUM(price + freight_value); all item rows/statuses.'
    FROM public.order_items
    UNION ALL
    SELECT 'Total payment value (BRL)', ROUND(SUM(payment_value), 2),
           'SUM(order_payments.payment_value); all payment rows/statuses.'
    FROM public.order_payments
    UNION ALL
    SELECT 'Average order value (BRL)',
           ROUND(SUM(payment_value) / NULLIF(COUNT(DISTINCT order_id), 0), 2),
           'Payment total divided by distinct order_ids with >=1 payment row; all statuses.'
    FROM public.order_payments
    UNION ALL
    SELECT 'Average review score', ROUND(AVG(review_score)::NUMERIC, 2),
           'AVG(order_reviews.review_score); denominator: review rows, not orders.'
    FROM public.order_reviews
    UNION ALL
    SELECT 'Average delivery time (days)',
           ROUND(AVG(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0)::NUMERIC, 2),
           'Delivered orders with both timestamps and nonnegative elapsed time.'
    FROM valid_delivered
    UNION ALL
    SELECT 'Eligible delivered orders', COUNT(*)::NUMERIC,
           'Denominator for average delivery time and late-delivery percentage.'
    FROM valid_delivered
    UNION ALL
    SELECT 'Late delivered orders', COUNT(*)::NUMERIC,
           'valid_delivered rows where actual customer delivery > estimated date.'
    FROM valid_delivered
    WHERE order_delivered_customer_date > order_estimated_delivery_date
    UNION ALL
    SELECT 'Late-delivery percentage',
           ROUND(100.0 * COUNT(*) FILTER (
               WHERE order_delivered_customer_date > order_estimated_delivery_date
           ) / NULLIF(COUNT(*), 0), 2),
           'Late delivered orders / eligible delivered orders * 100; strict > estimate.'
    FROM valid_delivered
    UNION ALL
    SELECT 'Delivered rows excluded for negative delivery time', COUNT(*)::NUMERIC,
           'Delivered rows with both actual/purchase timestamps and actual < purchase.'
    FROM public.orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date < order_purchase_timestamp
    UNION ALL
    SELECT 'Unique customers with orders', COUNT(*)::NUMERIC,
           'Distinct customer_unique_id values reached through orders.customer_id.'
    FROM person_order_counts
    UNION ALL
    SELECT 'Returning customers', COUNT(*)::NUMERIC,
           'customer_unique_id values with >1 distinct order_id.'
    FROM person_order_counts WHERE order_count > 1
    UNION ALL
    SELECT 'Returning customer percentage',
           ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / NULLIF(COUNT(*), 0), 2),
           'Returning customer_unique_id values / unique customer_unique_id values with orders * 100.'
    FROM person_order_counts
)
SELECT metric, value, population
FROM kpis
ORDER BY metric;

-- 4. Per-status values. First aggregate each one-to-many table to order_id;
-- the resulting order_rollup has exactly one row per order.
WITH item_by_order AS (
    SELECT order_id, SUM(price) AS item_sales_brl, SUM(freight_value) AS freight_brl
    FROM public.order_items
    GROUP BY order_id
), payment_by_order AS (
    SELECT order_id, SUM(payment_value) AS payment_brl
    FROM public.order_payments
    GROUP BY order_id
), order_rollup AS (
    SELECT o.order_id, o.order_status,
           COALESCE(i.item_sales_brl, 0) AS item_sales_brl,
           COALESCE(i.freight_brl, 0) AS freight_brl,
           COALESCE(p.payment_brl, 0) AS payment_brl
    FROM public.orders AS o
    LEFT JOIN item_by_order AS i ON i.order_id = o.order_id
    LEFT JOIN payment_by_order AS p ON p.order_id = o.order_id
)
SELECT order_status,
       COUNT(*) AS orders,
       ROUND(SUM(item_sales_brl), 2) AS item_sales_brl,
       ROUND(SUM(freight_brl), 2) AS freight_brl,
       ROUND(SUM(payment_brl), 2) AS payment_brl
FROM order_rollup
GROUP BY order_status
ORDER BY order_status;

-- 5. Prove the one-row-per-order rollup does not change any source total.
WITH item_by_order AS (
    SELECT order_id, SUM(price) AS item_sales_brl, SUM(freight_value) AS freight_brl
    FROM public.order_items GROUP BY order_id
), payment_by_order AS (
    SELECT order_id, SUM(payment_value) AS payment_brl
    FROM public.order_payments GROUP BY order_id
), order_rollup AS (
    SELECT o.order_id,
           COALESCE(i.item_sales_brl, 0) AS item_sales_brl,
           COALESCE(i.freight_brl, 0) AS freight_brl,
           COALESCE(p.payment_brl, 0) AS payment_brl
    FROM public.orders AS o
    LEFT JOIN item_by_order AS i ON i.order_id = o.order_id
    LEFT JOIN payment_by_order AS p ON p.order_id = o.order_id
)
SELECT (SELECT COUNT(*) FROM public.orders) AS source_orders,
       COUNT(*) AS rolled_up_orders,
       ROUND((SELECT SUM(price) FROM public.order_items), 2) AS source_item_sales_brl,
       ROUND(SUM(item_sales_brl), 2) AS rolled_up_item_sales_brl,
       ROUND((SELECT SUM(freight_value) FROM public.order_items), 2) AS source_freight_brl,
       ROUND(SUM(freight_brl), 2) AS rolled_up_freight_brl,
       ROUND((SELECT SUM(payment_value) FROM public.order_payments), 2) AS source_payment_brl,
       ROUND(SUM(payment_brl), 2) AS rolled_up_payment_brl,
       ROUND((SELECT SUM(price) FROM public.order_items) - SUM(item_sales_brl), 2) AS item_sales_difference_brl,
       ROUND((SELECT SUM(freight_value) FROM public.order_items) - SUM(freight_brl), 2) AS freight_difference_brl,
       ROUND((SELECT SUM(payment_value) FROM public.order_payments) - SUM(payment_brl), 2) AS payment_difference_brl
FROM order_rollup;

-- 6. Order-level reconciliation: child tables are separately summed by order.
-- Item amount is price + freight; payment amount is payment_value. A 1-cent
-- tolerance is used. Differences are diagnostic; source records are retained.
WITH item_by_order AS (
    SELECT order_id, SUM(price) AS item_sales_brl,
           SUM(freight_value) AS freight_brl,
           SUM(price + freight_value) AS item_plus_freight_brl
    FROM public.order_items
    GROUP BY order_id
), payment_by_order AS (
    SELECT order_id, SUM(payment_value) AS payment_brl
    FROM public.order_payments
    GROUP BY order_id
), compared AS (
    SELECT COALESCE(i.order_id, p.order_id) AS order_id,
           i.item_sales_brl, i.freight_brl, i.item_plus_freight_brl, p.payment_brl
    FROM item_by_order AS i
    FULL OUTER JOIN payment_by_order AS p USING (order_id)
)
SELECT COUNT(*) FILTER (WHERE item_plus_freight_brl IS NOT NULL AND payment_brl IS NOT NULL) AS comparable_orders,
       COUNT(*) FILTER (WHERE item_plus_freight_brl IS NOT NULL AND payment_brl IS NULL) AS item_only_orders,
       COUNT(*) FILTER (WHERE item_plus_freight_brl IS NULL AND payment_brl IS NOT NULL) AS payment_only_orders,
       ROUND(SUM(item_sales_brl), 2) AS item_sales_brl,
       ROUND(SUM(freight_brl), 2) AS freight_brl,
       ROUND(SUM(item_plus_freight_brl), 2) AS item_plus_freight_brl,
       ROUND(SUM(payment_brl), 2) AS payment_total_brl,
       COUNT(*) FILTER (
           WHERE item_plus_freight_brl IS NOT NULL AND payment_brl IS NOT NULL
             AND ABS(payment_brl - item_plus_freight_brl) > 0.01
       ) AS orders_over_01_difference,
       ROUND(COALESCE(SUM(ABS(payment_brl - item_plus_freight_brl)) FILTER (
           WHERE item_plus_freight_brl IS NOT NULL AND payment_brl IS NOT NULL
             AND ABS(payment_brl - item_plus_freight_brl) > 0.01
       ), 0), 2) AS absolute_difference_over_01_brl
FROM compared;

COMMIT;
