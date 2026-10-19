-- Olist 2.0 Phase 1B: raw-source table definitions for PostgreSQL.
-- Run once in a new, empty Olist database. This file deliberately does not
-- drop, truncate, or replace existing tables.
-- See README.md for data types, keys, and relationship rationale.

BEGIN;

CREATE TABLE public.customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    customer_zip_code_prefix VARCHAR(5) NOT NULL,
    customer_city TEXT NOT NULL,
    customer_state CHAR(2) NOT NULL
);

CREATE TABLE public.geolocation (
    geolocation_zip_code_prefix VARCHAR(5) NOT NULL,
    geolocation_lat NUMERIC NOT NULL,
    geolocation_lng NUMERIC NOT NULL,
    geolocation_city TEXT NOT NULL,
    geolocation_state CHAR(2) NOT NULL
);

CREATE TABLE public.products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT,
    product_name_lenght INTEGER,
    product_description_lenght INTEGER,
    product_photos_qty INTEGER,
    product_weight_g INTEGER,
    product_length_cm INTEGER,
    product_height_cm INTEGER,
    product_width_cm INTEGER
);

CREATE TABLE public.product_category_name_translation (
    product_category_name TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

CREATE TABLE public.sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5) NOT NULL,
    seller_city TEXT NOT NULL,
    seller_state CHAR(2) NOT NULL
);

CREATE TABLE public.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL REFERENCES public.customers (customer_id),
    order_status TEXT NOT NULL,
    order_purchase_timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    order_approved_at TIMESTAMP WITHOUT TIME ZONE,
    order_delivered_carrier_date TIMESTAMP WITHOUT TIME ZONE,
    order_delivered_customer_date TIMESTAMP WITHOUT TIME ZONE,
    order_estimated_delivery_date TIMESTAMP WITHOUT TIME ZONE NOT NULL
);

CREATE TABLE public.order_items (
    order_id TEXT NOT NULL REFERENCES public.orders (order_id),
    order_item_id INTEGER NOT NULL,
    product_id TEXT NOT NULL REFERENCES public.products (product_id),
    seller_id TEXT NOT NULL REFERENCES public.sellers (seller_id),
    shipping_limit_date TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    price NUMERIC NOT NULL,
    freight_value NUMERIC NOT NULL,
    CONSTRAINT order_items_pkey PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE public.order_payments (
    order_id TEXT NOT NULL REFERENCES public.orders (order_id),
    payment_sequential INTEGER NOT NULL,
    payment_type TEXT NOT NULL,
    payment_installments INTEGER NOT NULL,
    payment_value NUMERIC NOT NULL,
    CONSTRAINT order_payments_pkey PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE public.order_reviews (
    review_id TEXT NOT NULL,
    order_id TEXT NOT NULL REFERENCES public.orders (order_id),
    review_score INTEGER NOT NULL,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    review_answer_timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL
);

COMMIT;
