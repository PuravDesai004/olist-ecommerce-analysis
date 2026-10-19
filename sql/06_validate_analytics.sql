-- Evidence writes are atomic; source anomalies remain explicit assertions.
-- Olist 2.0 executable quality gates. Read-only; scripts/run_project.py fails
-- if ANY row is FAIL, NULL, or missing. Fixed baseline assertions verify this
-- historical snapshot; calculated measures are never forced to these values.
WITH
o AS MATERIALIZED (SELECT * FROM olist_analytics.v_orders),
i AS MATERIALIZED (SELECT * FROM olist_analytics.v_items),
p AS MATERIALIZED (SELECT * FROM olist_analytics.v_payments),
c AS MATERIALIZED (SELECT * FROM olist_analytics.v_customers),
r AS MATERIALIZED (SELECT * FROM olist_analytics.v_rfm),
m AS MATERIALIZED (SELECT * FROM olist_analytics.v_monthly),
so AS MATERIALIZED (SELECT * FROM olist_analytics.v_seller_orders),
sc AS MATERIALIZED (SELECT * FROM olist_analytics.v_seller_scorecard),
co AS MATERIALIZED (SELECT * FROM olist_analytics.v_category_orders),
cr AS MATERIALIZED (SELECT * FROM olist_analytics.v_cohort_retention),
raw_eligible AS MATERIALIZED (
  SELECT ord.order_id, cust.customer_unique_id, ord.order_purchase_timestamp::date AS date,
         DATE_TRUNC('month', ord.order_purchase_timestamp)::date AS month
  FROM public.orders ord JOIN public.customers cust USING (customer_id)
  WHERE ord.order_status = 'delivered' AND ord.order_purchase_timestamp < DATE '2018-09-01'
),
raw_first AS MATERIALIZED (
  SELECT customer_unique_id, MIN(month) AS cohort_month
  FROM raw_eligible GROUP BY customer_unique_id
),
raw_activity AS MATERIALIZED (
  SELECT f.cohort_month, e.month, COUNT(DISTINCT e.customer_unique_id) AS active
  FROM raw_eligible e JOIN raw_first f USING (customer_unique_id)
  GROUP BY f.cohort_month, e.month
),
raw_sizes AS MATERIALIZED (
  SELECT cohort_month, COUNT(*) AS size FROM raw_first GROUP BY cohort_month
),
tests(check_name, actual, expected) AS (
  SELECT 'source.customers.rows', COUNT(*)::numeric, 99441::numeric FROM public.customers
  UNION ALL SELECT 'source.geolocation.rows', COUNT(*),1000163 FROM public.geolocation
  UNION ALL SELECT 'source.items.rows',COUNT(*),112650 FROM public.order_items
  UNION ALL SELECT 'source.payments.rows',COUNT(*),103886 FROM public.order_payments
  UNION ALL SELECT 'source.reviews.rows',COUNT(*),99224 FROM public.order_reviews
  UNION ALL SELECT 'source.orders.rows',COUNT(*),99441 FROM public.orders
  UNION ALL SELECT 'source.products.rows',COUNT(*),32951 FROM public.products
  UNION ALL SELECT 'source.sellers.rows',COUNT(*),3095 FROM public.sellers
  UNION ALL SELECT 'source.translations.rows',COUNT(*),71
    FROM public.product_category_name_translation
  UNION ALL SELECT 'keys.customers.duplicates',COUNT(*)-COUNT(DISTINCT customer_id),0
    FROM public.customers
  UNION ALL SELECT 'keys.orders.duplicates',COUNT(*)-COUNT(DISTINCT order_id),0 FROM public.orders
  UNION ALL SELECT 'keys.items.duplicates',COUNT(*)-COUNT(DISTINCT(order_id,order_item_id)),0
    FROM public.order_items
  UNION ALL SELECT 'keys.payments.duplicates',COUNT(*)-COUNT(DISTINCT(order_id,payment_sequential)),0
    FROM public.order_payments
  UNION ALL SELECT 'keys.products.duplicates',COUNT(*)-COUNT(DISTINCT product_id),0 FROM public.products
  UNION ALL SELECT 'keys.sellers.duplicates',COUNT(*)-COUNT(DISTINCT seller_id),0 FROM public.sellers
  UNION ALL SELECT 'keys.translations.duplicates',COUNT(*)-COUNT(DISTINCT product_category_name),0
    FROM public.product_category_name_translation
  UNION ALL SELECT 'fk.orders.customers',COUNT(*),0 FROM public.orders x
    LEFT JOIN public.customers y USING(customer_id) WHERE y.customer_id IS NULL
  UNION ALL SELECT 'fk.items.orders',COUNT(*),0 FROM public.order_items x
    LEFT JOIN public.orders y USING(order_id) WHERE y.order_id IS NULL
  UNION ALL SELECT 'fk.items.products',COUNT(*),0 FROM public.order_items x
    LEFT JOIN public.products y USING(product_id) WHERE y.product_id IS NULL
  UNION ALL SELECT 'fk.items.sellers',COUNT(*),0 FROM public.order_items x
    LEFT JOIN public.sellers y USING(seller_id) WHERE y.seller_id IS NULL
  UNION ALL SELECT 'fk.payments.orders',COUNT(*),0 FROM public.order_payments x
    LEFT JOIN public.orders y USING(order_id) WHERE y.order_id IS NULL
  UNION ALL SELECT 'fk.reviews.orders',COUNT(*),0 FROM public.order_reviews x
    LEFT JOIN public.orders y USING(order_id) WHERE y.order_id IS NULL
  UNION ALL SELECT 'views.orders.grain',COUNT(*)-COUNT(DISTINCT order_id),0 FROM o
  UNION ALL SELECT 'views.orders.coverage',COUNT(*),(SELECT COUNT(*) FROM public.orders) FROM o
  UNION ALL SELECT 'views.items.grain',COUNT(*)-COUNT(DISTINCT(order_id,order_item_id)),0 FROM i
  UNION ALL SELECT 'views.items.coverage',COUNT(*),(SELECT COUNT(*) FROM public.order_items) FROM i
  UNION ALL SELECT 'views.payments.grain',COUNT(*)-COUNT(DISTINCT(order_id,payment_sequential)),0 FROM p
  UNION ALL SELECT 'views.payments.coverage',COUNT(*),(SELECT COUNT(*) FROM public.order_payments) FROM p
  UNION ALL SELECT 'views.customers.grain',COUNT(*)-COUNT(DISTINCT customer_unique_id),0 FROM c
  UNION ALL SELECT 'views.customers.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT customer_unique_id) FROM public.customers) FROM c
  UNION ALL SELECT 'views.rfm.grain',COUNT(*)-COUNT(DISTINCT customer_unique_id),0 FROM r
  UNION ALL SELECT 'views.monthly.grain',COUNT(*)-COUNT(DISTINCT month),0 FROM m
  UNION ALL SELECT 'views.seller_orders.grain',COUNT(*)-COUNT(DISTINCT(order_id,seller_id)),0 FROM so
  UNION ALL SELECT 'views.seller_orders.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT(order_id,seller_id)) FROM public.order_items) FROM so
  UNION ALL SELECT 'views.seller_scorecard.grain',COUNT(*)-COUNT(DISTINCT seller_id),0 FROM sc
  UNION ALL SELECT 'views.seller_scorecard.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT seller_id) FROM public.order_items) FROM sc
  UNION ALL SELECT 'views.category_orders.grain',COUNT(*)-COUNT(DISTINCT(order_id,category_key)),0 FROM co
  UNION ALL SELECT 'views.category_orders.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT(x.order_id,COALESCE(y.product_category_name,'__unknown__')))
     FROM public.order_items x JOIN public.products y USING(product_id)) FROM co
  UNION ALL SELECT 'views.cohort.grain',COUNT(*)-COUNT(DISTINCT(cohort_month,month_offset)),0 FROM cr
  UNION ALL SELECT 'views.products.grain',COUNT(*)-COUNT(DISTINCT product_id),0
    FROM olist_analytics.v_products
  UNION ALL SELECT 'views.products.coverage',COUNT(*),(SELECT COUNT(*) FROM public.products)
    FROM olist_analytics.v_products
  UNION ALL SELECT 'views.categories.grain',COUNT(*)-COUNT(DISTINCT category_key),0
    FROM olist_analytics.v_categories
  UNION ALL SELECT 'views.categories.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT COALESCE(product_category_name,'__unknown__')) FROM public.products)
    FROM olist_analytics.v_categories
  UNION ALL SELECT 'source.unknown_sentinel_collision',COUNT(*),0
    FROM public.products WHERE product_category_name='__unknown__'
  UNION ALL SELECT 'views.sellers.grain',COUNT(*)-COUNT(DISTINCT seller_id),0
    FROM olist_analytics.v_sellers
  UNION ALL SELECT 'views.sellers.coverage',COUNT(*),(SELECT COUNT(*) FROM public.sellers)
    FROM olist_analytics.v_sellers
  UNION ALL SELECT 'views.states.grain',COUNT(*)-COUNT(DISTINCT customer_state),0
    FROM olist_analytics.v_customer_states
  UNION ALL SELECT 'views.states.coverage',COUNT(*),
    (SELECT COUNT(DISTINCT customer_state) FROM public.customers)
    FROM olist_analytics.v_customer_states
  UNION ALL SELECT 'views.date.grain',COUNT(*)-COUNT(DISTINCT date),0 FROM olist_analytics.v_date
  UNION ALL SELECT 'views.date.contiguous',COUNT(*),MAX(date)-MIN(date)+1 FROM olist_analytics.v_date
  UNION ALL SELECT 'bi.date.coverage',COUNT(*),0 FROM o
    LEFT JOIN olist_analytics.v_date d ON d.date=o.purchase_date WHERE d.date IS NULL
  UNION ALL SELECT 'bi.customer.coverage',COUNT(*),0 FROM o LEFT JOIN c USING(customer_unique_id)
    WHERE c.customer_unique_id IS NULL
  UNION ALL SELECT 'bi.category.coverage',COUNT(*),0 FROM i
    LEFT JOIN olist_analytics.v_categories d USING(category_key) WHERE d.category_key IS NULL
  UNION ALL SELECT 'bi.state.coverage',COUNT(*),0 FROM o
    LEFT JOIN olist_analytics.v_customer_states d USING(customer_state) WHERE d.customer_state IS NULL
  UNION ALL SELECT 'baseline.item_sales',SUM(price),13591643.70 FROM public.order_items
  UNION ALL SELECT 'baseline.freight',SUM(freight_value),2251909.54 FROM public.order_items
  UNION ALL SELECT 'baseline.payments',SUM(payment_value),16008872.12 FROM public.order_payments
  UNION ALL SELECT 'baseline.paid_orders',COUNT(DISTINCT order_id),99440 FROM public.order_payments
  UNION ALL SELECT 'baseline.delivered_orders',COUNT(*),96478 FROM o WHERE order_status='delivered'
  UNION ALL SELECT 'baseline.aov',ROUND(SUM(payment_value)/COUNT(DISTINCT order_id),2),160.99
    FROM public.order_payments
  UNION ALL SELECT 'baseline.review_mean',ROUND(AVG(review_score),2),4.09 FROM public.order_reviews
  UNION ALL SELECT 'baseline.delivery_eligible',COUNT(*),96470 FROM o WHERE eligible_delivery
  UNION ALL SELECT 'baseline.delivery_mean',ROUND(AVG(delivery_days),2),12.56 FROM o
  UNION ALL SELECT 'baseline.late_orders',COUNT(*),7826 FROM o WHERE is_late
  UNION ALL SELECT 'baseline.late_rate',
    ROUND(100.0*COUNT(*) FILTER(WHERE is_late)
      /COUNT(*) FILTER(WHERE eligible_delivery),2),8.11 FROM o
  UNION ALL SELECT 'baseline.people',COUNT(*),96096 FROM c
  UNION ALL SELECT 'baseline.returning_people',COUNT(*),2997 FROM c WHERE is_repeat_customer
  UNION ALL SELECT 'baseline.returning_pct',
    ROUND(100.0*COUNT(*) FILTER(WHERE is_repeat_customer)/COUNT(*),2),3.12 FROM c
  UNION ALL SELECT 'rollup.order.item_sales',SUM(item_sales_brl),
    (SELECT SUM(price) FROM public.order_items) FROM o
  UNION ALL SELECT 'rollup.order.freight',SUM(freight_brl),
    (SELECT SUM(freight_value) FROM public.order_items) FROM o
  UNION ALL SELECT 'rollup.order.payments',SUM(payment_value_brl),
    (SELECT SUM(payment_value) FROM public.order_payments) FROM o
  UNION ALL SELECT 'rollup.order.item_rows',SUM(item_rows),
    (SELECT COUNT(*) FROM public.order_items) FROM o
  UNION ALL SELECT 'rollup.order.payment_rows',SUM(payment_rows),
    (SELECT COUNT(*) FROM public.order_payments) FROM o
  UNION ALL SELECT 'rollup.order.review_rows',SUM(review_rows),
    (SELECT COUNT(*) FROM public.order_reviews) FROM o
  UNION ALL SELECT 'rollup.order.review_sum',SUM(review_score_sum),
    (SELECT SUM(review_score) FROM public.order_reviews) FROM o
  UNION ALL SELECT 'rollup.order.review_mean',
    ROUND(SUM(review_score_sum)::numeric/NULLIF(SUM(review_rows),0),2),
    (SELECT ROUND(AVG(review_score),2) FROM public.order_reviews) FROM o
  UNION ALL SELECT 'rollup.order.aov',
    ROUND(SUM(payment_value_brl)/NULLIF(COUNT(*) FILTER(WHERE has_payment),0),2),
    (SELECT ROUND(SUM(payment_value)/COUNT(DISTINCT order_id),2) FROM public.order_payments) FROM o
  UNION ALL SELECT 'rollup.items.sales',SUM(price),(SELECT SUM(price) FROM public.order_items) FROM i
  UNION ALL SELECT 'rollup.items.freight',SUM(freight_value),
    (SELECT SUM(freight_value) FROM public.order_items) FROM i
  UNION ALL SELECT 'rollup.payments.amount',SUM(payment_value),
    (SELECT SUM(payment_value) FROM public.order_payments) FROM p
  UNION ALL SELECT 'rollup.monthly.orders',SUM(total_orders),(SELECT COUNT(*) FROM public.orders) FROM m
  UNION ALL SELECT 'rollup.monthly.sales',SUM(item_sales_brl),
    (SELECT SUM(price) FROM public.order_items) FROM m
  UNION ALL SELECT 'rollup.monthly.freight',SUM(freight_brl),
    (SELECT SUM(freight_value) FROM public.order_items) FROM m
  UNION ALL SELECT 'rollup.monthly.payments',SUM(payment_value_brl),
    (SELECT SUM(payment_value) FROM public.order_payments) FROM m
  UNION ALL SELECT 'monthly.growth_and_lag',COUNT(*),0 FROM m current
    LEFT JOIN m previous ON previous.month=(current.month-INTERVAL '1 month')::date
    WHERE current.previous_item_sales_brl IS DISTINCT FROM previous.item_sales_brl
       OR current.item_sales_growth_pct IS DISTINCT FROM
          100.0*(current.item_sales_brl-previous.item_sales_brl)
            /NULLIF(previous.item_sales_brl,0)
  UNION ALL SELECT 'monthly.cumulative_last',
    (SELECT cumulative_item_sales_brl FROM m ORDER BY month DESC LIMIT 1),
    (SELECT SUM(price) FROM public.order_items)
  UNION ALL SELECT 'monthly.calendar_gaps',
    (SELECT (12*(EXTRACT(YEAR FROM MAX(month))-EXTRACT(YEAR FROM MIN(month)))
              +EXTRACT(MONTH FROM MAX(month))-EXTRACT(MONTH FROM MIN(month))+1)::int FROM m),
    COUNT(*) FROM m
  UNION ALL SELECT 'rfm.eligible_people',COUNT(*),
    (SELECT COUNT(DISTINCT e.customer_unique_id) FROM raw_eligible e
     WHERE EXISTS(SELECT 1 FROM public.order_payments pp WHERE pp.order_id=e.order_id)) FROM r
  UNION ALL SELECT 'rfm.eligible_orders',SUM(frequency),
    (SELECT COUNT(*) FROM raw_eligible e
     WHERE EXISTS(SELECT 1 FROM public.order_payments pp WHERE pp.order_id=e.order_id)) FROM r
  UNION ALL SELECT 'rfm.eligible_money',SUM(monetary_brl),
    (SELECT SUM(pp.payment_value) FROM public.order_payments pp
     JOIN raw_eligible e USING(order_id)) FROM r
  UNION ALL SELECT 'rfm.invalid_scores',COUNT(*),0 FROM r
    WHERE reference_date<>DATE '2018-09-01' OR recency_days<0
       OR frequency<1 OR r_score NOT BETWEEN 1 AND 5
       OR f_score NOT BETWEEN 1 AND 5 OR m_score NOT BETWEEN 1 AND 5 OR segment IS NULL
  UNION ALL SELECT 'rfm.recency_calculation',COUNT(*),0 FROM r
    WHERE recency_days<>reference_date-last_purchase_date
  UNION ALL SELECT 'rfm.person_assignment',COUNT(*),0 FROM (
    (SELECT customer_unique_id FROM r EXCEPT
     SELECT DISTINCT e.customer_unique_id FROM raw_eligible e
     WHERE EXISTS(SELECT 1 FROM public.order_payments pp WHERE pp.order_id=e.order_id))
    UNION ALL
    (SELECT DISTINCT e.customer_unique_id FROM raw_eligible e
     WHERE EXISTS(SELECT 1 FROM public.order_payments pp WHERE pp.order_id=e.order_id)
     EXCEPT SELECT customer_unique_id FROM r)
  ) missing
  UNION ALL SELECT 'rfm.segment_dimension_coverage',COUNT(*),0 FROM c
    WHERE rfm_segment IS NULL OR
      ((rfm_segment='Not eligible') IS DISTINCT FROM (rfm_frequency IS NULL))
  UNION ALL SELECT 'cohort.month_zero_100',COUNT(*),0 FROM cr
    WHERE month_offset=0 AND (retention_pct<>100 OR active_customers<>cohort_size)
  UNION ALL SELECT 'cohort.person_coverage',SUM(cohort_size),
    (SELECT COUNT(*) FROM raw_first) FROM cr WHERE month_offset=0
  UNION ALL SELECT 'cohort.invalid_cells',COUNT(*),0 FROM cr
    WHERE activity_month>=observation_end OR month_offset<0 OR active_customers>cohort_size
       OR retention_pct<0 OR retention_pct>100 OR activity_month<cohort_month
  UNION ALL SELECT 'cohort.expected_grid_size',COUNT(*),
    (SELECT SUM(12*(2018-EXTRACT(YEAR FROM cohort_month))
              +8-EXTRACT(MONTH FROM cohort_month)+1) FROM raw_sizes) FROM cr
  UNION ALL SELECT 'cohort.independent_raw_activity',COUNT(*),0 FROM cr
    LEFT JOIN raw_activity a ON a.cohort_month=cr.cohort_month AND a.month=cr.activity_month
    LEFT JOIN raw_sizes s ON s.cohort_month=cr.cohort_month
    WHERE cr.active_customers IS DISTINCT FROM COALESCE(a.active,0)
       OR cr.cohort_size IS DISTINCT FROM s.size
       OR cr.retention_pct IS DISTINCT FROM 100.0*COALESCE(a.active,0)/NULLIF(s.size,0)
  UNION ALL SELECT 'rollup.seller.sales',SUM(seller_item_sales_brl),
    (SELECT SUM(price) FROM public.order_items) FROM so
  UNION ALL SELECT 'rollup.seller.freight',SUM(seller_freight_brl),
    (SELECT SUM(freight_value) FROM public.order_items) FROM so
  UNION ALL SELECT 'rollup.seller.items',SUM(item_rows),
    (SELECT COUNT(*) FROM public.order_items) FROM so
  UNION ALL SELECT 'rollup.scorecard.sales',SUM(item_sales_brl),
    (SELECT SUM(price) FROM public.order_items) FROM sc
  UNION ALL SELECT 'rollup.scorecard.participations',SUM(seller_orders),(SELECT COUNT(*) FROM so) FROM sc
  UNION ALL SELECT 'scorecard.shipping_denominator',COUNT(*),0 FROM sc
    WHERE shipping_limit_met_pct_proxy<0 OR shipping_limit_met_pct_proxy>100
       OR eligible_shipping_orders>seller_orders
  UNION ALL SELECT 'rollup.category.sales',SUM(category_item_sales_brl),
    (SELECT SUM(price) FROM public.order_items) FROM co
  UNION ALL SELECT 'rollup.category.freight',SUM(category_freight_brl),
    (SELECT SUM(freight_value) FROM public.order_items) FROM co
  UNION ALL SELECT 'source.review_id_repeats',COUNT(*)-COUNT(DISTINCT review_id),814
    FROM public.order_reviews
  UNION ALL SELECT 'source.review_order_repeats',COUNT(*)-COUNT(DISTINCT order_id),551
    FROM public.order_reviews
  UNION ALL SELECT 'source.geolocation_duplicate_excess',COUNT(*)-COUNT(DISTINCT(
      geolocation_zip_code_prefix,geolocation_lat,geolocation_lng,geolocation_city,geolocation_state
    )),261831 FROM public.geolocation
  UNION ALL SELECT 'source.product_missing_category',COUNT(*),610 FROM public.products
    WHERE product_category_name IS NULL
  UNION ALL SELECT 'source.untranslated_product_rows',COUNT(*),13 FROM public.products x
    LEFT JOIN public.product_category_name_translation y USING(product_category_name)
    WHERE x.product_category_name IS NOT NULL AND y.product_category_name IS NULL
  UNION ALL SELECT 'source.approval_after_carrier',COUNT(*),1359 FROM public.orders
    WHERE order_approved_at>order_delivered_carrier_date
  UNION ALL SELECT 'source.carrier_after_delivery',COUNT(*),23 FROM public.orders
    WHERE order_delivered_carrier_date>order_delivered_customer_date
  UNION ALL SELECT 'reconciliation.comparable',COUNT(*),98665 FROM o WHERE has_items AND has_payment
  UNION ALL SELECT 'reconciliation.item_only',COUNT(*),1 FROM o WHERE has_items AND NOT has_payment
  UNION ALL SELECT 'reconciliation.payment_only',COUNT(*),775 FROM o WHERE has_payment AND NOT has_items
  UNION ALL SELECT 'reconciliation.over_01',COUNT(*),303 FROM o
    WHERE ABS(payment_difference_brl)>0.01
  UNION ALL SELECT 'reconciliation.absolute_difference',SUM(ABS(payment_difference_brl)),3269.22
    FROM o WHERE ABS(payment_difference_brl)>0.01
)
SELECT check_name, actual, expected,
       CASE WHEN actual IS NOT NULL AND expected IS NOT NULL AND actual=expected
            THEN 'PASS' ELSE 'FAIL' END AS status
FROM tests ORDER BY check_name;