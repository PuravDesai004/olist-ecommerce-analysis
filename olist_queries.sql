-- Olist 2.0 | PostgreSQL analysis | database: olist2
-- Prerequisite: sql/05_reporting_views.sql. Sources remain unchanged.
-- Original 29 queries are individually audited from Git by scripts/run_project.py.
-- Consolidations: B1+B6+I5 -> Q01; B3+I6 -> Q03. Other original analyses retained.
-- Nominal BRL: item sales=price, freight and payments are separate. All statuses
-- unless stated. No profit inferred; review/delivery associations are not causal.
BEGIN TRANSACTION READ ONLY;

-- Q01 | Order status mix and non-delivered states
-- Legacy: B1,B6,I5. One row/status; denominator all orders.
SELECT order_status, order_status = 'delivered' AS is_delivered, COUNT(*) AS total_orders,
 ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_all_orders
FROM public.orders GROUP BY order_status ORDER BY total_orders DESC, order_status;

-- Q02 | Top customer cities, distinguishing states
-- Legacy: B2. Customer records and distinct people are separate measures.
SELECT customer_city, customer_state, COUNT(*) AS customer_records,
 COUNT(DISTINCT customer_unique_id) AS unique_people
FROM public.customers GROUP BY customer_city, customer_state
ORDER BY customer_records DESC, customer_state, customer_city LIMIT 5;

-- Q03 | Payment-method transaction and amount contribution
-- Legacy: B3,I6. Method order counts overlap for multi-method orders.
SELECT payment_type, COUNT(*) AS payment_transactions,
 COUNT(DISTINCT order_id) AS orders_using_method,
 ROUND(SUM(payment_value), 2) AS payment_value_brl,
 ROUND(AVG(payment_value), 2) AS avg_transaction_value_brl,
 ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS transaction_share_pct,
 ROUND(100.0 * SUM(payment_value) / NULLIF(SUM(SUM(payment_value)) OVER (), 0), 2)
   AS payment_value_share_pct
FROM public.order_payments GROUP BY payment_type ORDER BY payment_value_brl DESC;

-- Q04 | Source review-record distribution
-- Legacy: B4. Repeated IDs retained; denominator source review rows.
SELECT review_score, COUNT(*) AS review_records,
 ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_review_records
FROM public.order_reviews GROUP BY review_score ORDER BY review_score;

-- Q05 | Seller geographic footprint
-- Legacy: B5. Registered source sellers, not seller-order participations.
SELECT seller_state, COUNT(*) AS sellers FROM public.sellers
GROUP BY seller_state ORDER BY sellers DESC, seller_state;

-- Q06 | Installments by payment method
-- Legacy: B7. Unweighted transaction means; zero installment values preserved.
SELECT payment_type, COUNT(*) AS payment_rows,
 ROUND(AVG(payment_installments), 2) AS avg_installments,
 MAX(payment_installments) AS max_installments,
 COUNT(*) FILTER (WHERE payment_installments = 0) AS zero_installment_rows
FROM public.order_payments GROUP BY payment_type ORDER BY avg_installments DESC;

-- Q07 | Annual orders, item sales, freight and payments
-- Legacy: B8. One row/year; parent grain prevents payment-row count inflation.
SELECT EXTRACT(YEAR FROM purchase_date)::int AS year, COUNT(*) AS orders,
 COUNT(*) FILTER (WHERE has_payment) AS orders_with_payment,
 ROUND(SUM(item_sales_brl), 2) AS item_sales_brl,
 ROUND(SUM(freight_brl), 2) AS freight_brl,
 ROUND(SUM(payment_value_brl), 2) AS payment_value_brl
FROM olist_analytics.v_orders GROUP BY year ORDER BY year;

-- Q08 | Categories with highest mean item price
-- Legacy: I1. Item-weighted mean, sample size shown, unknown categories retained.
SELECT c.category_key, c.category_label, COUNT(*) AS item_rows,
 ROUND(AVG(i.price), 2) AS avg_item_price_brl
FROM olist_analytics.v_items i JOIN olist_analytics.v_categories c USING (category_key)
GROUP BY c.category_key, c.category_label
ORDER BY avg_item_price_brl DESC, c.category_key LIMIT 10;

-- Q09 | Category sales and contribution
-- Legacy: I2. All source categories, including unmapped/null; order counts overlap.
SELECT c.category_key, c.category_label, COUNT(*) AS item_rows,
 COUNT(DISTINCT i.order_id) AS category_orders, ROUND(SUM(i.price), 2) AS item_sales_brl,
 ROUND(100.0 * SUM(i.price) / NULLIF(SUM(SUM(i.price)) OVER (), 0), 2) AS sales_share_pct
FROM olist_analytics.v_items i JOIN olist_analytics.v_categories c USING (category_key)
GROUP BY c.category_key, c.category_label ORDER BY item_sales_brl DESC, c.category_key;

-- Q10 | Top sellers by distinct order volume
-- Legacy: I3. Seller item sales are not allocated customer payments.
SELECT seller_id, seller_city, seller_state, seller_orders, item_rows,
 ROUND(item_sales_brl, 2) AS item_sales_brl
FROM olist_analytics.v_seller_scorecard ORDER BY seller_orders DESC, seller_id LIMIT 10;

-- Q11 | Customer-state payment value and order AOV
-- Legacy: I4. Denominator: orders with payment records, including zero amounts.
SELECT customer_state, COUNT(*) AS total_orders,
 COUNT(*) FILTER (WHERE has_payment) AS orders_with_payment,
 ROUND(SUM(payment_value_brl), 2) AS payment_value_brl,
 ROUND(SUM(item_sales_brl), 2) AS item_sales_brl,
 ROUND(SUM(payment_value_brl) / NULLIF(COUNT(*) FILTER (WHERE has_payment), 0), 2) AS aov_brl
FROM olist_analytics.v_orders GROUP BY customer_state
ORDER BY payment_value_brl DESC, customer_state;

-- Q12 | Category freight burden
-- Legacy: I7. Ratio of totals, not unweighted mean of per-item ratios.
SELECT c.category_key, c.category_label, COUNT(*) AS item_rows,
 ROUND(AVG(i.price), 2) AS avg_item_price_brl,
 ROUND(AVG(i.freight_value), 2) AS avg_item_freight_brl,
 ROUND(100.0 * SUM(i.freight_value) / NULLIF(SUM(i.price), 0), 2) AS freight_to_sales_pct
FROM olist_analytics.v_items i JOIN olist_analytics.v_categories c USING (category_key)
GROUP BY c.category_key, c.category_label ORDER BY freight_to_sales_pct DESC;

-- Q13 | Orders with more than three items
-- Legacy: I8. Source item rows are the available item unit; no quantity column.
SELECT order_id, item_rows, ROUND(item_sales_brl, 2) AS item_sales_brl,
 ROUND(freight_brl, 2) AS freight_brl FROM olist_analytics.v_orders
WHERE item_rows > 3 ORDER BY item_rows DESC, order_id;

-- Q14 | Returning people and payment value
-- Legacy: I9. Person grain; location changes must not split people.
SELECT customer_unique_id, lifetime_orders,
 ROUND(lifetime_payment_value_brl, 2) AS payment_value_brl
FROM olist_analytics.v_customers WHERE is_repeat_customer
ORDER BY lifetime_orders DESC, customer_unique_id;

-- Q15 | Monthly orders and financial trends
-- Legacy: I10. Purchase-month attribution, internal gaps filled; boundary months flagged.
SELECT month, total_orders, orders_with_payment, ROUND(item_sales_brl, 2) AS item_sales_brl,
 ROUND(freight_brl, 2) AS freight_brl, ROUND(payment_value_brl, 2) AS payment_value_brl,
 ROUND(aov_brl, 2) AS aov_brl, is_boundary_month
FROM olist_analytics.v_monthly ORDER BY month;

-- Q16 | Category review association, equal weight per reviewed order-category
-- Legacy: I11. Unique order-category pairs; multi-category orders are shared.
SELECT c.category_key, c.category_label, COUNT(*) AS reviewed_category_orders,
 ROUND(AVG(o.avg_order_review_score), 2) AS avg_order_review_score
FROM olist_analytics.v_category_orders o JOIN olist_analytics.v_categories c USING (category_key)
WHERE o.avg_order_review_score IS NOT NULL GROUP BY c.category_key, c.category_label
HAVING COUNT(*) > 100 ORDER BY avg_order_review_score DESC, c.category_key LIMIT 5;

-- Q17 | Actual, estimated and late delivery durations
-- Legacy: I12. Valid delivered orders; fractional elapsed days; deterministic sample.
SELECT order_id, ROUND(delivery_days, 2) AS actual_delivery_days,
 ROUND(EXTRACT(EPOCH FROM (order_estimated_delivery_date
   - order_purchase_timestamp)) / 86400.0, 2) AS estimated_delivery_days,
 ROUND(delay_days, 2) AS signed_delay_days, is_late
FROM olist_analytics.v_orders WHERE eligible_delivery
ORDER BY order_purchase_timestamp, order_id LIMIT 20;

-- Q18 | Regional delivery reliability
-- Legacy: I13. Eligible delivered denominator; signed and late-only means distinguished.
SELECT customer_state, COUNT(*) AS eligible_deliveries,
 COUNT(*) FILTER (WHERE is_late) AS late_orders,
 ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_rate_pct,
 ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
 ROUND(AVG(delay_days), 2) AS avg_signed_delay_days,
 ROUND(AVG(delay_days) FILTER (WHERE is_late), 2) AS avg_late_delay_days
FROM olist_analytics.v_orders WHERE eligible_delivery GROUP BY customer_state
ORDER BY late_rate_pct DESC, customer_state;

-- Q19 | Products never present in order_items
-- Legacy: I14. Empty result valid; NULL categories do not disqualify products.
SELECT p.product_id, p.product_category_name FROM public.products p
WHERE NOT EXISTS (SELECT 1 FROM public.order_items i WHERE i.product_id = p.product_id)
ORDER BY p.product_id;

-- Q20 | Delivery timing and reviews: association, not causation
-- Legacy: I15. One eligible order per row; equal-order review weighting.
WITH buckets AS (
 SELECT *, CASE WHEN delay_days < 0 THEN 'Early'
   WHEN delay_days = 0 THEN 'Exactly estimate'
   WHEN delay_days <= 7 THEN 'Late >0 to 7 days' ELSE 'Late >7 days' END AS delivery_bucket
 FROM olist_analytics.v_orders WHERE eligible_delivery
)
SELECT delivery_bucket, COUNT(*) AS delivered_orders,
 COUNT(avg_order_review_score) AS reviewed_orders,
 ROUND(AVG(avg_order_review_score), 2) AS avg_order_review_score,
 ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM buckets GROUP BY delivery_bucket ORDER BY delivered_orders DESC;

-- Q21 | Historical RFM customer segmentation
-- Legacy: A1. Fixed purchase cutoff; delivered snapshot is not historical status reconstruction.
SELECT customer_unique_id, reference_date, last_purchase_date, recency_days, frequency,
 ROUND(monetary_brl, 2) AS monetary_brl, r_score, f_score, m_score, segment
FROM olist_analytics.v_rfm ORDER BY monetary_brl DESC, customer_unique_id;

-- Q22 | Seller ranks per purchase month with genuine sales ties
-- Legacy: A2. Competition ranks <=3 may contain more than three sellers.
WITH sales AS (
 SELECT purchase_month, seller_id, SUM(seller_item_sales_brl) AS sales
 FROM olist_analytics.v_seller_orders GROUP BY purchase_month, seller_id
), ranked AS (
 SELECT *, RANK() OVER (PARTITION BY purchase_month ORDER BY sales DESC) AS seller_rank
 FROM sales
)
SELECT purchase_month, seller_id, ROUND(sales, 2) AS item_sales_brl, seller_rank
FROM ranked WHERE seller_rank <= 3 ORDER BY purchase_month, seller_rank, seller_id;

-- Q23 | Month-over-month item sales growth
-- Legacy: A3. Previous calendar month; first/zero denominator growth remains NULL.
SELECT month, ROUND(item_sales_brl, 2) AS item_sales_brl,
 ROUND(previous_item_sales_brl, 2) AS previous_item_sales_brl,
 ROUND(item_sales_growth_pct, 2) AS growth_pct, is_boundary_month
FROM olist_analytics.v_monthly ORDER BY month;

-- Q24 | Monthly orders and running order total
-- Legacy: A4. Explicit ROWS window; every order counted once.
SELECT month, total_orders,
 SUM(total_orders) OVER (ORDER BY month ROWS UNBOUNDED PRECEDING) AS cumulative_orders
FROM olist_analytics.v_monthly ORDER BY month;

-- Q25 | Exactly up to three products per source category
-- Legacy: A5. Missing categories retained; exact sales then product key breaks ties.
WITH sales AS (
 SELECT category_key, product_id, SUM(price) AS sales
 FROM olist_analytics.v_items GROUP BY category_key, product_id
), ranked AS (
 SELECT *, ROW_NUMBER() OVER (
   PARTITION BY category_key ORDER BY sales DESC, product_id
 ) AS position FROM sales
)
SELECT r.category_key, c.category_label, r.product_id,
 ROUND(r.sales, 2) AS item_sales_brl, r.position
FROM ranked r JOIN olist_analytics.v_categories c USING (category_key)
WHERE position <= 3 ORDER BY r.category_key, r.position;

-- Q26 | Repeat versus one-time customer coverage
-- Legacy: A6. All people, all statuses; static full-snapshot repeat metric.
SELECT CASE WHEN is_repeat_customer THEN 'Repeat' ELSE 'One-time' END AS customer_type,
 COUNT(*) AS people, SUM(lifetime_orders) AS orders,
 ROUND(SUM(lifetime_item_sales_brl), 2) AS item_sales_brl,
 ROUND(SUM(lifetime_payment_value_brl), 2) AS payment_value_brl,
 ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS people_share_pct
FROM olist_analytics.v_customers GROUP BY is_repeat_customer ORDER BY customer_type;

-- Q27 | Executive KPIs and source coverage
-- New. Review sum/count reproduces raw-review-record weighting.
SELECT MIN(purchase_date) AS first_purchase_date, MAX(purchase_date) AS last_purchase_date,
 COUNT(*) AS total_orders,
 COUNT(*) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
 COUNT(*) FILTER (WHERE has_payment) AS orders_with_payment,
 ROUND(SUM(item_sales_brl), 2) AS item_sales_brl, ROUND(SUM(freight_brl), 2) AS freight_brl,
 ROUND(SUM(payment_value_brl), 2) AS payment_value_brl,
 ROUND(SUM(payment_value_brl) / NULLIF(COUNT(*) FILTER (WHERE has_payment), 0), 2) AS aov_brl,
 ROUND(SUM(review_score_sum)::numeric / NULLIF(SUM(review_rows), 0), 2) AS source_review_mean,
 COUNT(*) FILTER (WHERE eligible_delivery) AS eligible_deliveries,
 COUNT(*) FILTER (WHERE is_late) AS late_orders, ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
 ROUND(100.0 * COUNT(*) FILTER (WHERE is_late)
   / NULLIF(COUNT(*) FILTER (WHERE eligible_delivery), 0), 2) AS late_rate_pct,
 COUNT(DISTINCT customer_unique_id) AS unique_people
FROM olist_analytics.v_orders;

-- Q28 | Category Pareto contribution and the 80-percent crossing
-- New. Includes category crossing 80%; does not assume 20% of categories suffice.
WITH sales AS (
 SELECT category_key, SUM(price) AS sales FROM olist_analytics.v_items GROUP BY category_key
), pareto AS (
 SELECT *, SUM(sales) OVER () AS total,
 SUM(sales) OVER (ORDER BY sales DESC, category_key ROWS UNBOUNDED PRECEDING) AS cumulative,
 COALESCE(SUM(sales) OVER (
   ORDER BY sales DESC, category_key ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
 ), 0) AS previous_cumulative,
 ROW_NUMBER() OVER (ORDER BY sales DESC, category_key) AS position FROM sales
)
SELECT p.position, p.category_key, c.category_label, ROUND(p.sales, 2) AS item_sales_brl,
 ROUND(100.0 * p.sales / NULLIF(p.total, 0), 2) AS sales_share_pct,
 ROUND(100.0 * p.cumulative / NULLIF(p.total, 0), 2) AS cumulative_share_pct,
 p.previous_cumulative < 0.8 * p.total AS needed_to_reach_80pct
FROM pareto p JOIN olist_analytics.v_categories c USING (category_key) ORDER BY p.position;

-- Q29 | First-observed customer acquisition
-- New. First observed source order, not verified marketing acquisition.
SELECT acquisition_month, COUNT(*) AS first_observed_people,
 COUNT(*) FILTER (WHERE is_repeat_customer) AS eventually_returning_people,
 ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat_customer) / COUNT(*), 2) AS snapshot_repeat_pct
FROM olist_analytics.v_customers GROUP BY acquisition_month ORDER BY acquisition_month;

-- Q30 | Observed intervals to the next purchase
-- New. LEAD uses stable person/time/order sequence; final purchases right-censored.
WITH sequenced AS (
 SELECT customer_unique_id, order_purchase_timestamp,
 LEAD(order_purchase_timestamp) OVER (
   PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id
 ) AS next_purchase FROM olist_analytics.v_orders
), gaps AS (
 SELECT EXTRACT(EPOCH FROM (next_purchase - order_purchase_timestamp)) / 86400.0 AS days
 FROM sequenced WHERE next_purchase IS NOT NULL
)
SELECT COUNT(*) AS observed_repeat_intervals, ROUND(AVG(days), 2) AS avg_days,
 ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days)::numeric, 2) AS median_days,
 COUNT(*) FILTER (WHERE days < 1) AS intervals_under_one_day FROM gaps;

-- Q31 | Delivered-purchase monthly cohort retention
-- New. Fixed observation end, first-observed cohorts; future cells omitted, observed gaps zero.
SELECT cohort_month, month_offset, cohort_size, active_customers,
 ROUND(retention_pct, 2) AS retention_pct, observation_end
FROM olist_analytics.v_cohort_retention
WHERE cohort_month >= DATE '2017-01-01' AND month_offset <= 6
ORDER BY cohort_month, month_offset;

-- Q32 | RFM segment contribution within the matching eligible population
-- New. No attribution of future/ineligible orders to a supposedly historical segment.
SELECT r.segment, COUNT(DISTINCT o.customer_unique_id) AS people, COUNT(*) AS orders,
 ROUND(SUM(o.item_sales_brl), 2) AS item_sales_brl,
 ROUND(SUM(o.payment_value_brl), 2) AS payment_value_brl,
 ROUND(100.0 * SUM(o.payment_value_brl)
   / NULLIF(SUM(SUM(o.payment_value_brl)) OVER (), 0), 2) AS payment_share_pct
FROM olist_analytics.v_orders o JOIN olist_analytics.v_rfm r USING (customer_unique_id)
WHERE o.order_status = 'delivered' AND o.has_payment
 AND o.order_purchase_timestamp < DATE '2018-09-01'
GROUP BY r.segment ORDER BY payment_value_brl DESC;

-- Q33 | Seller-state item sales and order participation
-- New. Order counts non-additive across seller states in a multi-seller order.
SELECT s.seller_state, COUNT(DISTINCT so.seller_id) AS active_sellers,
 COUNT(*) AS seller_order_participations, COUNT(DISTINCT so.order_id) AS marketplace_orders,
 ROUND(SUM(so.seller_item_sales_brl), 2) AS item_sales_brl,
 ROUND(SUM(so.seller_item_sales_brl) / NULLIF(COUNT(DISTINCT so.order_id), 0), 2)
   AS regional_item_value_per_order_brl
FROM olist_analytics.v_seller_orders so JOIN public.sellers s USING (seller_id)
GROUP BY s.seller_state ORDER BY item_sales_brl DESC, s.seller_state;

-- Q34 | Seller performance scorecard
-- New. Transparent metrics and sample sizes; no arbitrary composite score.
SELECT seller_id, seller_city, seller_state, seller_orders, eligible_delivered_orders,
 ROUND(item_sales_brl, 2) AS item_sales_brl,
 ROUND(seller_order_item_aov_brl, 2) AS seller_order_item_aov_brl,
 ROUND(late_rate_pct, 2) AS late_rate_pct, ROUND(avg_delivery_days, 2) AS avg_delivery_days,
 reviewed_seller_orders, ROUND(avg_order_review_score, 2) AS avg_order_review_score,
 eligible_shipping_orders,
 ROUND(shipping_limit_met_pct_proxy, 2) AS shipping_limit_met_pct_proxy,
 sales_rank, delivery_monitoring_flag
FROM olist_analytics.v_seller_scorecard ORDER BY item_sales_brl DESC, seller_id LIMIT 20;

-- Q35 | Category delivery and review associations
-- New. Unique order-category pairs; delivery outcomes shared across categories.
SELECT c.category_key, c.category_label, COUNT(*) AS eligible_category_orders,
 COUNT(*) FILTER (WHERE o.is_late) AS late_category_orders,
 ROUND(100.0 * COUNT(*) FILTER (WHERE o.is_late) / COUNT(*), 2) AS late_rate_pct,
 ROUND(AVG(o.delivery_days), 2) AS avg_delivery_days,
 COUNT(o.avg_order_review_score) AS reviewed_category_orders,
 ROUND(AVG(o.avg_order_review_score), 2) AS avg_order_review_score
FROM olist_analytics.v_category_orders o JOIN olist_analytics.v_categories c USING (category_key)
WHERE o.eligible_delivery GROUP BY c.category_key, c.category_label
ORDER BY eligible_category_orders DESC, c.category_key;

-- Q36 | Installment distribution within payment method
-- New. Transaction-level distribution, including zero-installment irregularities.
SELECT payment_type, payment_installments, COUNT(*) AS payment_rows,
 ROUND(SUM(payment_value), 2) AS payment_value_brl,
 ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY payment_type), 2)
   AS within_method_transaction_pct
FROM public.order_payments GROUP BY payment_type, payment_installments
ORDER BY payment_type, payment_installments;

-- Q37 | Order-level financial reconciliation
-- New. BRL0.01 tolerance only for comparable orders; missing sides classified separately.
WITH classified AS (
 SELECT *, CASE WHEN NOT has_items AND NOT has_payment THEN 'Neither source'
   WHEN NOT has_items THEN 'Payment only' WHEN NOT has_payment THEN 'Items only'
   WHEN ABS(payment_difference_brl) > 0.01 THEN 'Difference over BRL0.01'
   ELSE 'Within BRL0.01' END AS reconciliation_status FROM olist_analytics.v_orders
)
SELECT reconciliation_status, COUNT(*) AS orders,
 ROUND(SUM(item_sales_brl + freight_brl), 2) AS items_and_freight_brl,
 ROUND(SUM(payment_value_brl), 2) AS payment_value_brl,
 ROUND(SUM(ABS(payment_difference_brl)), 2) AS comparable_absolute_difference_brl
FROM classified GROUP BY reconciliation_status ORDER BY reconciliation_status;

-- Q38 | Largest comparable financial differences
-- New. Investigation evidence; no unproven attribution to discounts, fees or fraud.
SELECT order_id, order_status, item_rows, payment_rows,
 ROUND(item_sales_brl + freight_brl, 2) AS items_and_freight_brl,
 ROUND(payment_value_brl, 2) AS payment_value_brl,
 ROUND(payment_difference_brl, 2) AS signed_difference_brl
FROM olist_analytics.v_orders
WHERE has_items AND has_payment AND ABS(payment_difference_brl) > 0.01
ORDER BY ABS(payment_difference_brl) DESC, order_id LIMIT 20;
COMMIT;
