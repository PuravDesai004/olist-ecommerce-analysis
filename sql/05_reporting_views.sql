-- Olist 2.0 reporting layer. Source tables and records are never changed.
-- Inspect existing analytical objects and dependencies before executing this file.
-- All money is nominal BRL. Item sales exclude freight; payments are separate.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';
CREATE SCHEMA IF NOT EXISTS olist_analytics;
COMMENT ON SCHEMA olist_analytics IS
  'Olist 2.0 project-owned reporting views; source data remains in public.';

CREATE OR REPLACE VIEW olist_analytics.v_categories AS
SELECT DISTINCT COALESCE(p.product_category_name, '__unknown__') AS category_key,
       p.product_category_name,
       t.product_category_name_english,
       COALESCE(t.product_category_name_english, p.product_category_name,
                'Unknown category') AS category_label,
       p.product_category_name IS NULL AS is_missing_category,
       p.product_category_name IS NOT NULL
         AND t.product_category_name IS NULL AS is_untranslated_category
FROM public.products p
LEFT JOIN public.product_category_name_translation t
  ON t.product_category_name = p.product_category_name;
COMMENT ON VIEW olist_analytics.v_categories IS
  'Grain: one source category key; __unknown__ represents NULL, never an invented source value.';

CREATE OR REPLACE VIEW olist_analytics.v_products AS
SELECT p.*, COALESCE(p.product_category_name, '__unknown__') AS category_key,
       c.category_label
FROM public.products p
JOIN olist_analytics.v_categories c
  ON c.category_key = COALESCE(p.product_category_name, '__unknown__');
COMMENT ON VIEW olist_analytics.v_products IS 'Grain: one product_id; source attributes unchanged.';

CREATE OR REPLACE VIEW olist_analytics.v_sellers AS
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state
FROM public.sellers;
COMMENT ON VIEW olist_analytics.v_sellers IS 'Grain: one seller_id; seller geography.';

CREATE OR REPLACE VIEW olist_analytics.v_customer_states AS
SELECT DISTINCT customer_state FROM public.customers;
COMMENT ON VIEW olist_analytics.v_customer_states IS 'Grain: one customer_state; order geography role.';

CREATE OR REPLACE VIEW olist_analytics.v_date AS
SELECT d::date AS date, EXTRACT(YEAR FROM d)::int AS year,
       EXTRACT(QUARTER FROM d)::int AS quarter,
       EXTRACT(MONTH FROM d)::int AS month_number,
       TO_CHAR(d, 'Mon') AS month_name,
       DATE_TRUNC('month', d)::date AS month_start,
       TO_CHAR(d, 'YYYY-MM') AS year_month,
       (EXTRACT(YEAR FROM d) * 100 + EXTRACT(MONTH FROM d))::int AS year_month_sort
FROM GENERATE_SERIES(
  (SELECT DATE_TRUNC('year', MIN(order_purchase_timestamp)) FROM public.orders),
  (SELECT DATE_TRUNC('year', MAX(order_purchase_timestamp))
          + INTERVAL '1 year' - INTERVAL '1 day' FROM public.orders),
  INTERVAL '1 day'
) g(d);
COMMENT ON VIEW olist_analytics.v_date IS 'Grain: one contiguous calendar date; full source purchase years.';

CREATE OR REPLACE VIEW olist_analytics.v_orders AS
WITH items AS (
  SELECT order_id, COUNT(*) AS item_rows, SUM(price) AS item_sales_brl,
         SUM(freight_value) AS freight_brl
  FROM public.order_items GROUP BY order_id
), payments AS (
  SELECT order_id, COUNT(*) AS payment_rows, SUM(payment_value) AS payment_value_brl
  FROM public.order_payments GROUP BY order_id
), reviews AS (
  SELECT order_id, COUNT(*) AS review_rows, SUM(review_score) AS review_score_sum,
         AVG(review_score)::numeric AS avg_order_review_score
  FROM public.order_reviews GROUP BY order_id
), joined AS (
  SELECT o.*, c.customer_unique_id, c.customer_state,
         o.order_purchase_timestamp::date AS purchase_date,
         DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
         COALESCE(i.item_rows, 0) AS item_rows,
         COALESCE(i.item_sales_brl, 0) AS item_sales_brl,
         COALESCE(i.freight_brl, 0) AS freight_brl,
         i.order_id IS NOT NULL AS has_items,
         COALESCE(p.payment_rows, 0) AS payment_rows,
         COALESCE(p.payment_value_brl, 0) AS payment_value_brl,
         p.order_id IS NOT NULL AS has_payment,
         COALESCE(r.review_rows, 0) AS review_rows,
         COALESCE(r.review_score_sum, 0) AS review_score_sum,
         r.avg_order_review_score,
         COALESCE(o.order_status = 'delivered'
           AND o.order_delivered_customer_date >= o.order_purchase_timestamp,
           false) AS eligible_delivery
  FROM public.orders o
  JOIN public.customers c ON c.customer_id = o.customer_id
  LEFT JOIN items i ON i.order_id = o.order_id
  LEFT JOIN payments p ON p.order_id = o.order_id
  LEFT JOIN reviews r ON r.order_id = o.order_id
)
SELECT j.*,
       CASE WHEN eligible_delivery THEN
         EXTRACT(EPOCH FROM (order_delivered_customer_date
                            - order_purchase_timestamp)) / 86400.0
       END AS delivery_days,
       CASE WHEN eligible_delivery THEN
         EXTRACT(EPOCH FROM (order_delivered_customer_date
                            - order_estimated_delivery_date)) / 86400.0
       END AS delay_days,
       CASE WHEN eligible_delivery THEN
         order_delivered_customer_date > order_estimated_delivery_date
       END AS is_late,
       CASE WHEN has_items AND has_payment THEN
         payment_value_brl - item_sales_brl - freight_brl
       END AS payment_difference_brl
FROM joined j;
COMMENT ON VIEW olist_analytics.v_orders IS
  'Grain: one order_id. Independent child rollups prevent fanout. Missing child amounts=0; missing review/delivery averages=NULL. All statuses.';

CREATE OR REPLACE VIEW olist_analytics.v_items AS
SELECT i.*, o.customer_id, c.customer_unique_id, c.customer_state,
       o.order_status, o.order_purchase_timestamp::date AS purchase_date,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
       COALESCE(p.product_category_name, '__unknown__') AS category_key
FROM public.order_items i
JOIN public.orders o ON o.order_id = i.order_id
JOIN public.customers c ON c.customer_id = o.customer_id
JOIN public.products p ON p.product_id = i.product_id;
COMMENT ON VIEW olist_analytics.v_items IS
  'Grain: (order_id,order_item_id). Only item price/freight; order payment amounts are deliberately absent.';

CREATE OR REPLACE VIEW olist_analytics.v_payments AS
SELECT p.*, c.customer_unique_id, c.customer_state, o.order_status,
       o.order_purchase_timestamp::date AS purchase_date
FROM public.order_payments p
JOIN public.orders o ON o.order_id = p.order_id
JOIN public.customers c ON c.customer_id = o.customer_id;
COMMENT ON VIEW olist_analytics.v_payments IS
  'Grain: (order_id,payment_sequential). Payment date unavailable; purchase date used for attribution.';

CREATE OR REPLACE VIEW olist_analytics.v_rfm AS
WITH rfm AS (
  SELECT customer_unique_id, DATE '2018-09-01' AS reference_date,
         MAX(purchase_date) AS last_purchase_date,
         DATE '2018-09-01' - MAX(purchase_date) AS recency_days,
         COUNT(*) AS frequency, SUM(payment_value_brl) AS monetary_brl
  FROM olist_analytics.v_orders
  WHERE order_status = 'delivered' AND has_payment
    AND order_purchase_timestamp < DATE '2018-09-01'
  GROUP BY customer_unique_id
), scored AS (
  SELECT rfm.*,
         CASE WHEN recency_days <= 30 THEN 5 WHEN recency_days <= 90 THEN 4
              WHEN recency_days <= 180 THEN 3 WHEN recency_days <= 365 THEN 2
              ELSE 1 END AS r_score,
         CASE WHEN frequency = 1 THEN 1 WHEN frequency = 2 THEN 3 ELSE 5 END AS f_score,
         NTILE(5) OVER (ORDER BY monetary_brl, customer_unique_id) AS m_score
  FROM rfm
)
SELECT scored.*,
       CASE WHEN r_score >= 4 AND f_score >= 3 AND m_score >= 4 THEN 'High value active'
            WHEN r_score <= 2 THEN 'Lapsed'
            WHEN frequency = 1 THEN 'Single purchase'
            ELSE 'Other repeat' END AS segment
FROM scored;
COMMENT ON VIEW olist_analytics.v_rfm IS
  'Grain: eligible person. Fixed purchase cutoff 2018-09-01; final delivered-status snapshot and payment-record orders. NTILE splits monetary ties deterministically. Segments are explicit descriptive policies.';

CREATE OR REPLACE VIEW olist_analytics.v_customers AS
WITH people AS (
  SELECT customer_unique_id, MIN(purchase_date) AS first_purchase_date,
         MAX(purchase_date) AS last_purchase_date, COUNT(*) AS lifetime_orders,
         COUNT(*) FILTER (WHERE has_payment) AS lifetime_paid_orders,
         SUM(item_sales_brl) AS lifetime_item_sales_brl,
         SUM(payment_value_brl) AS lifetime_payment_value_brl
  FROM olist_analytics.v_orders GROUP BY customer_unique_id
)
SELECT p.*, DATE_TRUNC('month', p.first_purchase_date)::date AS acquisition_month,
       p.lifetime_orders > 1 AS is_repeat_customer,
       r.reference_date, r.recency_days, r.frequency AS rfm_frequency,
       r.monetary_brl AS rfm_monetary_brl, r.r_score, r.f_score, r.m_score,
       COALESCE(r.segment, 'Not eligible') AS rfm_segment
FROM people p LEFT JOIN olist_analytics.v_rfm r USING (customer_unique_id);
COMMENT ON VIEW olist_analytics.v_customers IS
  'Grain: person with any order, all statuses. Lifetime fields are static diagnostics; RFM fields use separate fixed eligibility. Location lives on order facts.';

CREATE OR REPLACE VIEW olist_analytics.v_monthly AS
WITH monthly AS (
  SELECT purchase_month AS month, COUNT(*) AS total_orders,
         COUNT(*) FILTER (WHERE has_payment) AS orders_with_payment,
         SUM(item_sales_brl) AS item_sales_brl, SUM(freight_brl) AS freight_brl,
         SUM(payment_value_brl) AS payment_value_brl
  FROM olist_analytics.v_orders GROUP BY purchase_month
), calendar AS (
  SELECT DISTINCT month_start AS month FROM olist_analytics.v_date
  WHERE month_start BETWEEN (SELECT MIN(month) FROM monthly)
                        AND (SELECT MAX(month) FROM monthly)
), filled AS (
  SELECT c.month, COALESCE(m.total_orders, 0) AS total_orders,
         COALESCE(m.orders_with_payment, 0) AS orders_with_payment,
         COALESCE(m.item_sales_brl, 0) AS item_sales_brl,
         COALESCE(m.freight_brl, 0) AS freight_brl,
         COALESCE(m.payment_value_brl, 0) AS payment_value_brl,
         c.month IN ((SELECT MIN(month) FROM monthly),
                     (SELECT MAX(month) FROM monthly)) AS is_boundary_month
  FROM calendar c LEFT JOIN monthly m USING (month)
), lagged AS (
  SELECT f.*, LAG(item_sales_brl) OVER (ORDER BY month) AS previous_item_sales_brl
  FROM filled f
)
SELECT l.*, payment_value_brl / NULLIF(orders_with_payment, 0) AS aov_brl,
       100.0 * (item_sales_brl - previous_item_sales_brl)
         / NULLIF(previous_item_sales_brl, 0) AS item_sales_growth_pct,
       SUM(item_sales_brl) OVER (
         ORDER BY month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS cumulative_item_sales_brl
FROM lagged l;
COMMENT ON VIEW olist_analytics.v_monthly IS
  'Grain: purchase month, internal gaps filled. Growth uses exact item sales and previous calendar month. Boundary/sparse source months require disclosure.';

CREATE OR REPLACE VIEW olist_analytics.v_seller_orders AS
WITH seller_items AS (
  SELECT order_id, seller_id, COUNT(*) AS item_rows,
         SUM(price) AS seller_item_sales_brl, SUM(freight_value) AS seller_freight_brl,
         MIN(shipping_limit_date) AS earliest_shipping_limit
  FROM public.order_items GROUP BY order_id, seller_id
)
SELECT s.*, o.purchase_date, o.purchase_month, o.customer_unique_id, o.customer_state,
       o.order_status, o.eligible_delivery, o.delivery_days, o.delay_days, o.is_late,
       o.avg_order_review_score,
       COALESCE(o.order_delivered_carrier_date >= o.order_purchase_timestamp,
                false) AS eligible_shipping_proxy,
       CASE WHEN o.order_delivered_carrier_date >= o.order_purchase_timestamp
            THEN o.order_delivered_carrier_date <= s.earliest_shipping_limit
       END AS met_shipping_limit_proxy
FROM seller_items s JOIN olist_analytics.v_orders o USING (order_id);
COMMENT ON VIEW olist_analytics.v_seller_orders IS
  'Grain: (order_id,seller_id). Seller basket subtotal is item sales, not allocated payments. Delivery/reviews/carrier handoff are order outcomes attributed to participating sellers; not causal seller performance.';

CREATE OR REPLACE VIEW olist_analytics.v_seller_scorecard AS
WITH scores AS (
  SELECT seller_id, COUNT(*) AS seller_orders, SUM(item_rows) AS item_rows,
         SUM(seller_item_sales_brl) AS item_sales_brl,
         SUM(seller_freight_brl) AS freight_brl,
         SUM(seller_item_sales_brl) / COUNT(*) AS seller_order_item_aov_brl,
         COUNT(*) FILTER (WHERE eligible_delivery) AS eligible_delivered_orders,
         COUNT(*) FILTER (WHERE is_late) AS late_orders,
         100.0 * COUNT(*) FILTER (WHERE is_late)
           / NULLIF(COUNT(*) FILTER (WHERE eligible_delivery), 0) AS late_rate_pct,
         AVG(delivery_days) AS avg_delivery_days,
         COUNT(avg_order_review_score) AS reviewed_seller_orders,
         AVG(avg_order_review_score) AS avg_order_review_score,
         COUNT(*) FILTER (WHERE eligible_shipping_proxy) AS eligible_shipping_orders,
         100.0 * COUNT(*) FILTER (WHERE met_shipping_limit_proxy)
           / NULLIF(COUNT(*) FILTER (WHERE eligible_shipping_proxy), 0)
             AS shipping_limit_met_pct_proxy
  FROM olist_analytics.v_seller_orders GROUP BY seller_id
), baseline AS (
  SELECT 100.0 * COUNT(*) FILTER (WHERE is_late)
           / NULLIF(COUNT(*) FILTER (WHERE eligible_delivery), 0) AS late_rate
  FROM olist_analytics.v_orders
)
SELECT sc.*, s.seller_city, s.seller_state,
       RANK() OVER (ORDER BY sc.item_sales_brl DESC) AS sales_rank,
       CASE WHEN eligible_delivered_orders < 30 THEN 'Small sample'
            WHEN late_rate_pct > b.late_rate THEN 'Above overall late-rate baseline'
            ELSE 'At or below overall late-rate baseline' END AS delivery_monitoring_flag
FROM scores sc JOIN public.sellers s USING (seller_id) CROSS JOIN baseline b;
COMMENT ON VIEW olist_analytics.v_seller_scorecard IS
  'Grain: active seller. Transparent multi-metric scorecard, no arbitrary composite score. 30 delivered orders is a practical monitoring floor, not statistical significance.';

CREATE OR REPLACE VIEW olist_analytics.v_category_orders AS
WITH category_items AS (
  SELECT order_id, category_key, COUNT(*) AS item_rows,
         SUM(price) AS category_item_sales_brl, SUM(freight_value) AS category_freight_brl
  FROM olist_analytics.v_items GROUP BY order_id, category_key
)
SELECT i.*, o.purchase_date, o.customer_unique_id, o.customer_state, o.order_status,
       o.eligible_delivery, o.delivery_days, o.delay_days, o.is_late,
       o.avg_order_review_score
FROM category_items i JOIN olist_analytics.v_orders o USING (order_id);
COMMENT ON VIEW olist_analytics.v_category_orders IS
  'Grain: (order_id,category_key). Category item amounts additive; order delivery/review attribution shared across categories. Use distinct order counts across categories.';

CREATE OR REPLACE VIEW olist_analytics.v_cohort_retention AS
WITH eligible AS (
  SELECT DISTINCT customer_unique_id, purchase_month
  FROM olist_analytics.v_orders
  WHERE order_status = 'delivered' AND purchase_date < DATE '2018-09-01'
), first_month AS (
  SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
  FROM eligible GROUP BY customer_unique_id
), sizes AS (
  SELECT cohort_month, COUNT(*) AS cohort_size
  FROM first_month GROUP BY cohort_month
), active AS (
  SELECT f.cohort_month, e.purchase_month, COUNT(*) AS active_customers
  FROM eligible e JOIN first_month f USING (customer_unique_id)
  GROUP BY f.cohort_month, e.purchase_month
), grid AS (
  SELECT s.*, g.activity_month::date AS activity_month
  FROM sizes s
  CROSS JOIN LATERAL GENERATE_SERIES(
    s.cohort_month::timestamp, TIMESTAMP '2018-08-01', INTERVAL '1 month'
  ) g(activity_month)
)
SELECT g.cohort_month, g.activity_month,
       (12 * (EXTRACT(YEAR FROM g.activity_month) - EXTRACT(YEAR FROM g.cohort_month))
         + EXTRACT(MONTH FROM g.activity_month)
         - EXTRACT(MONTH FROM g.cohort_month))::int AS month_offset,
       g.cohort_size, COALESCE(a.active_customers, 0) AS active_customers,
       100.0 * COALESCE(a.active_customers, 0) / NULLIF(g.cohort_size, 0)
         AS retention_pct, DATE '2018-09-01' AS observation_end
FROM grid g LEFT JOIN active a
  ON a.cohort_month = g.cohort_month AND a.purchase_month = g.activity_month;
COMMENT ON VIEW olist_analytics.v_cohort_retention IS
  'Grain: (cohort_month,month_offset). Delivered snapshot, first observed purchase, fixed full-month window ending 2018-09-01. Future cells absent; observed missing activity zero; cohort_size repeats and must not be summed across offsets.';
COMMIT;
