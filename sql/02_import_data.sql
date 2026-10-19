-- Olist 2.0 Phase 1C: import the original CSVs with the psql client.
-- Run from psql against the existing database after 01_create_tables.sql.
-- This script never deletes, truncates, or replaces data.
--
-- Safe rerun behavior:
--   * all nine tables already have the expected source row counts: import is
--     skipped and the existing 03_validate_import.sql checks are run;
--   * all nine tables are empty: import proceeds in foreign-key dependency order;
--   * any other state: current counts are printed and the script exits without
--     changing database rows. Inspect partial data manually before retrying.
--
-- Use psql -f, not pgAdmin Query Tool: \copy is a psql client command so the
-- user's Windows account reads CSVs from OneDrive, not the PostgreSQL service.

\set ON_ERROR_STOP on

SELECT
    (SELECT COUNT(*) = 0 FROM public.customers)
    AND (SELECT COUNT(*) = 0 FROM public.geolocation)
    AND (SELECT COUNT(*) = 0 FROM public.order_items)
    AND (SELECT COUNT(*) = 0 FROM public.order_payments)
    AND (SELECT COUNT(*) = 0 FROM public.order_reviews)
    AND (SELECT COUNT(*) = 0 FROM public.orders)
    AND (SELECT COUNT(*) = 0 FROM public.products)
    AND (SELECT COUNT(*) = 0 FROM public.sellers)
    AND (SELECT COUNT(*) = 0 FROM public.product_category_name_translation)
    AS all_empty,
    (SELECT COUNT(*) = 99441 FROM public.customers)
    AND (SELECT COUNT(*) = 1000163 FROM public.geolocation)
    AND (SELECT COUNT(*) = 112650 FROM public.order_items)
    AND (SELECT COUNT(*) = 103886 FROM public.order_payments)
    AND (SELECT COUNT(*) = 99224 FROM public.order_reviews)
    AND (SELECT COUNT(*) = 99441 FROM public.orders)
    AND (SELECT COUNT(*) = 32951 FROM public.products)
    AND (SELECT COUNT(*) = 3095 FROM public.sellers)
    AND (SELECT COUNT(*) = 71 FROM public.product_category_name_translation)
    AS all_expected
\gset

\if :all_expected
    \echo All nine tables already match the audited source row counts. Skipping import and running validation.
    \ir 03_validate_import.sql
    \quit
\endif

\if :all_empty
    \echo All nine target tables are empty. Importing source CSVs.
\else
    \echo Import stopped: target tables contain a partial or unexpected row-count state. No rows were changed.
    SELECT 'customers' AS table_name, COUNT(*) AS actual_rows FROM public.customers
    UNION ALL SELECT 'geolocation', COUNT(*) FROM public.geolocation
    UNION ALL SELECT 'order_items', COUNT(*) FROM public.order_items
    UNION ALL SELECT 'order_payments', COUNT(*) FROM public.order_payments
    UNION ALL SELECT 'order_reviews', COUNT(*) FROM public.order_reviews
    UNION ALL SELECT 'orders', COUNT(*) FROM public.orders
    UNION ALL SELECT 'products', COUNT(*) FROM public.products
    UNION ALL SELECT 'sellers', COUNT(*) FROM public.sellers
    UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM public.product_category_name_translation
    ORDER BY table_name;
    \quit 3
\endif

BEGIN;

-- Keep the empty-table preflight true for the duration of the bulk load.
LOCK TABLE public.customers, public.geolocation, public.order_items,
           public.order_payments, public.order_reviews, public.orders,
           public.products, public.sellers,
           public.product_category_name_translation
IN SHARE ROW EXCLUSIVE MODE;

DO $preflight$
BEGIN
    IF EXISTS (SELECT 1 FROM public.customers LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.geolocation LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.order_items LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.order_payments LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.order_reviews LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.orders LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.products LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.sellers LIMIT 1)
       OR EXISTS (SELECT 1 FROM public.product_category_name_translation LIMIT 1)
    THEN
        RAISE EXCEPTION 'Import stopped: rows appeared after the empty-table preflight; no CSV rows were loaded';
    END IF;
END
$preflight$;

-- Empty CSV fields are imported as SQL NULL. Source rows and duplicates are retained.
\copy public.customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.products (product_id, product_category_name, product_name_lenght, product_description_lenght, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.product_category_name_translation (product_category_name, product_category_name_english) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')
\copy public.order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp) FROM 'C:/Users/purav/OneDrive/Desktop/Olist/data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', NULL '')

COMMIT;

-- A separate call to 03_validate_import.sql produces the detailed post-import checks.
