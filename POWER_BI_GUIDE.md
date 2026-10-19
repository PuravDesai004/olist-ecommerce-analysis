# Olist 2.0 - manual Power BI handoff

The reporting contract is defined in sql/05_reporting_views.sql. The historical
execution record in sql/verification_results.json covers release 2097d69; follow
the README's manual SQL checks to verify the current database. No Power BI model,
DAX measure or dashboard has been executed in Desktop. The original screenshots
and dashboard PDF are Olist 1.0 artifacts.

## First connection

1. Complete the manual SQL verification steps in the README.
2. Open Power BI Desktop yourself. Choose **Home > Get data > PostgreSQL database**.
3. Enter server **localhost:5432**, database **olist2**, and select **Import**.
4. Choose Database authentication, username **postgres**, and enter the password
   locally. Never put it in SQL, DAX or Git.
5. If Desktop presents an encryption warning for this local server, decide
   whether to accept it or configure a trusted certificate yourself. This project
   does not change PostgreSQL security settings.
6. In Navigator, choose the olist_analytics views below and **Transform data**.
   Rename the queries exactly as shown for the DAX examples.

Current Desktop releases include the PostgreSQL provider. Do not install another
provider unless your installation reports that it needs one.
[Microsoft PostgreSQL connector](https://learn.microsoft.com/en-us/power-query/connectors/postgresql)

## Import contract

A regular view computes from PostgreSQL sources when queried. Import mode keeps
a local Power BI snapshot until refreshed.

| SQL view | Model name | One row per | Important measures and dimensions |
| --- | --- | --- | --- |
| v_orders | FactOrders | order_id | Date, status, person, customer state; independent item/freight/payment/review rollups. Missing child totals/counts zero; missing averages/durations NULL. |
| v_items | FactItems | (order_id, order_item_id) | Product, seller, category, person/state/date, price and freight_value; no repeated order payment totals. |
| v_payments | FactPayments | (order_id, payment_sequential) | Method, installments, payment_value, person/state/purchase date. Source has no payment timestamp. |
| v_seller_orders | FactSellerOrders | (order_id, seller_id) | Seller item subtotal/freight/count, shared order delivery/reviews, carrier-deadline proxy. No allocated payments. |
| v_category_orders | FactCategoryOrders | (order_id, category_key) | Category item amounts and shared order delivery/review outcomes. Use distinct orders across categories. |
| v_customers | DimCustomer | customer_unique_id | First/last observed purchase, lifetime diagnostics, repeat flag and fixed-reference RFM fields. Geography belongs to orders. |
| v_products | DimProduct | product_id | Original product fields, source category, category key and label. |
| v_sellers | DimSeller | seller_id | Seller city/state/ZIP. |
| v_categories | DimCategory | category_key | English label, Portuguese fallback, missing/untranslated flags. __unknown__ represents a NULL category. |
| v_customer_states | DimCustomerState | customer_state | Customer/order geography, separate from seller geography. |
| v_date | DimDate | date | Contiguous full purchase years; year/quarter/month/year-month sort fields. |
| v_cohort_retention | CohortRetention | (cohort_month, month_offset) | Fixed delivered-purchase window through August 2018. Observed zeroes included; future cells absent. Cohort size repeats by offset. |
| v_rfm | Usually omit | Eligible person | Already included in DimCustomer; useful for SQL inspection. |
| v_monthly | Optional SQLMonthlyChecks | Purchase month | SQL growth, AOV and cumulative checks; disconnected and hidden if imported. |
| v_seller_scorecard | Optional SQLSellerChecks | Active seller | Full-period validation reference; disconnected and hidden if imported. |

Original source columns retain their names. The model names are Power BI query
aliases. Derived measures use explicit names.

### Data types

- IDs, ZIP prefixes, state codes and category keys: Text.
- Purchase/calendar dates: Date. Source timestamps: Date/Time.
- Counts, installments and scores: Whole number. Flags: True/False.
- BRL amounts: Fixed decimal number; display two decimals.
- Ratios, fractional days and averages: Decimal number.
- DAX percent measures return fractions. SQL columns ending _pct return 0-100;
  divide by 100 before applying Power BI percentage formatting.
- Set numeric dimension diagnostics to **Do not summarize** and prefer explicit
  measures. Keep original product_name_lenght/product_description_lenght spelling.

## Relationships and filtering

Create **one-to-many, single direction from dimension to fact** relationships.
Review and remove unwanted automatically inferred relationships.

| One side | Many side |
| --- | --- |
| DimDate[date] | purchase_date in all five fact tables |
| DimCustomer[customer_unique_id] | customer_unique_id in all five fact tables |
| DimCustomerState[customer_state] | customer_state in all five fact tables |
| DimProduct[product_id] | FactItems[product_id] |
| DimSeller[seller_id] | FactItems[seller_id] and FactSellerOrders[seller_id] |
| DimCategory[category_key] | FactItems[category_key] and FactCategoryOrders[category_key] |

Do not link facts to each other. Do not add DimCategory -> DimProduct as a
second path. Seller geography is an attribute of DimSeller, not customer state.
Raw geolocation ZIP prefixes are nonunique and must not become a relationship key.

Keep CohortRetention disconnected from general date/customer/state slicers.
Its aggregation and eligibility are fixed; arbitrary dynamic cohorts would need
person-month activity and newly verified measures. Give it its own cohort-month
and offset controls and a visible snapshot label.

Mark DimDate[date] as the date table. Disable automatic date/time tables.
Sort month_name by month_number and year_month by year_month_sort. The dimension
contains full years; set report date coverage within the actual source range.

Two interaction boundaries are intentional:

- Category/product/seller filters reach item or participation facts. They do not
  allocate payment value to those entities or filter FactOrders.
- Date filters reach activity facts but do not recompute static RFM scores or
  lifetime fields in DimCustomer.

Use measures from the appropriate fact. A category chart can filter item sales,
but must not appear to filter all-order payment AOV. State/date/customer filters
support both. Configure visual interactions accordingly. Hide category attributes
on DimProduct when using the conformed DimCategory slicer.
[Microsoft star-schema guidance](https://learn.microsoft.com/en-us/power-bi/guidance/star-schema)

## DAX examples for this exact model

These definitions are justified by the view contract but have not been run in
Desktop. Adapt table names only if you choose different query aliases, then
validate every measure. SQL results do not prove Desktop relationships or DAX.

### Executive measures

~~~dax
Orders = COUNTROWS(FactOrders)

Item Sales BRL = COALESCE(SUM(FactItems[price]), 0)

Freight BRL = COALESCE(SUM(FactItems[freight_value]), 0)

Payment Value BRL = SUM(FactOrders[payment_value_brl])

Orders With Payment =
CALCULATE(COUNTROWS(FactOrders), FactOrders[has_payment] = TRUE())

AOV BRL = DIVIDE([Payment Value BRL], [Orders With Payment])

Delivered Orders =
CALCULATE([Orders], FactOrders[order_status] = "delivered")

Average Source Review Score =
DIVIDE(SUM(FactOrders[review_score_sum]), SUM(FactOrders[review_rows]))

Eligible Delivered Orders =
CALCULATE([Orders], FactOrders[eligible_delivery] = TRUE())

Late Orders = CALCULATE([Orders], FactOrders[is_late] = TRUE())

Late Delivery % = DIVIDE([Late Orders], [Eligible Delivered Orders])

Average Delivery Days = AVERAGE(FactOrders[delivery_days])

Item Orders = DISTINCTCOUNT(FactItems[order_id])

Freight To Item Sales % = DIVIDE([Freight BRL], [Item Sales BRL])
~~~

Item Orders counts orders represented in the item context. It differs from all
Orders when an order lacks items. The review measure preserves source-record
weighting; averaging per-order review averages gives a different metric.

### Monthly comparisons

~~~dax
Previous Month Item Sales BRL =
CALCULATE([Item Sales BRL], DATEADD(DimDate[date], -1, MONTH))

Item Sales MoM % =
DIVIDE([Item Sales BRL] - [Previous Month Item Sales BRL],
       [Previous Month Item Sales BRL])

Running Item Sales BRL =
CALCULATE(
    [Item Sales BRL],
    FILTER(ALLSELECTED(DimDate), DimDate[date] <= MAX(DimDate[date]))
)
~~~

Use DimDate[year_month] on a monthly axis. Undefined first/zero-denominator growth
stays BLANK. Compare matching populations with Q23. Label partial boundary and
sparse closing source months before interpreting apparent growth or decline.

### Customers and fixed RFM

~~~dax
Customers = DISTINCTCOUNT(FactOrders[customer_unique_id])

Returning Customers =
COUNTROWS(
    FILTER(
        VALUES(FactOrders[customer_unique_id]),
        CALCULATE(COUNTROWS(FactOrders)) > 1
    )
)

Returning Customer % = DIVIDE([Returning Customers], [Customers])

RFM Eligible People =
CALCULATE(COUNTROWS(DimCustomer), DimCustomer[rfm_segment] <> "Not eligible")

RFM Monetary BRL = SUM(DimCustomer[rfm_monetary_brl])

RFM Eligible Payment Value BRL =
CALCULATE(
    [Payment Value BRL],
    FactOrders[order_status] = "delivered",
    FactOrders[has_payment] = TRUE(),
    KEEPFILTERS(DimDate[date] < DATE(2018, 9, 1))
)
~~~

Returning Customers is recalculated in the selected order context. RFM is fixed
at 2018-09-01 using delivered-snapshot orders purchased before that date with a
payment record. This is not a reconstruction of historical status knowledge.
R thresholds are 30/90/180/365 days; F scores are 1/3/5 for one/two/three-plus
orders; monetary quintiles use person-key tie-breaking. NTILE may split equal
amounts. Segment labels describe an explicit policy, not predictive value.

### Cohort matrix

~~~dax
Cohort Active Customers = SUM(CohortRetention[active_customers])

Cohort Size =
SUMX(
    VALUES(CohortRetention[cohort_month]),
    CALCULATE(MAX(CohortRetention[cohort_size]))
)

Cohort Retention % =
IF(
    HASONEVALUE(CohortRetention[month_offset]),
    DIVIDE([Cohort Active Customers], [Cohort Size])
)
~~~

Matrix rows: cohort_month; columns: month_offset; values: retention percent.
Month 0 must be 100%. Totals across offsets are deliberately BLANK. Column totals
pool only observed cohorts using cohort-size weighting. Future cells stay BLANK.

### Seller and category delivery

~~~dax
Seller Item Sales BRL = SUM(FactSellerOrders[seller_item_sales_brl])

Seller Orders = DISTINCTCOUNT(FactSellerOrders[order_id])

Seller Order Item AOV BRL = DIVIDE([Seller Item Sales BRL], [Seller Orders])

Seller Eligible Deliveries =
CALCULATE(DISTINCTCOUNT(FactSellerOrders[order_id]),
          FactSellerOrders[eligible_delivery] = TRUE())

Seller Late Orders =
CALCULATE(DISTINCTCOUNT(FactSellerOrders[order_id]),
          FactSellerOrders[is_late] = TRUE())

Seller Late % = DIVIDE([Seller Late Orders], [Seller Eligible Deliveries])

Category Eligible Deliveries =
CALCULATE(DISTINCTCOUNT(FactCategoryOrders[order_id]),
          FactCategoryOrders[eligible_delivery] = TRUE())

Category Late Orders =
CALCULATE(DISTINCTCOUNT(FactCategoryOrders[order_id]),
          FactCategoryOrders[is_late] = TRUE())

Category Late % = DIVIDE([Category Late Orders], [Category Eligible Deliveries])

Category Reviewed-Order Score =
CALCULATE(
    AVERAGEX(
        VALUES(FactCategoryOrders[order_id]),
        CALCULATE(MAX(FactCategoryOrders[avg_order_review_score]))
    ),
    FactCategoryOrders[eligible_delivery] = TRUE()
)
~~~

Seller AOV is an item subtotal per represented order, not payment AOV. Reviews
and delivery belong to orders and are shared with participating sellers/categories.
The shipping-deadline measure uses the order-level carrier timestamp against the
seller's earliest item deadline; it cannot isolate which seller caused a delay.
The SQL monitoring floor of 30 eligible deliveries is practical, not a significance test.

## Three pages to build manually

### Executive Overview

- Cards: item sales, payment value, orders, payment AOV; name each population.
- Monthly item-sales line, MoM chart and boundary/sparse-month coverage notes.
- Category item-sales contribution/Pareto chart using DimCategory.
- Customer-state sales/payments and AOV comparison.
- Date/status/customer-state slicers; deliberate category/seller interactions.

### Customer Intelligence

- Customers and selected-context returning-customer rate.
- Fixed RFM segment counts and eligible payment contribution; reference date visible.
- Cohort retention matrix with its own snapshot controls.
- First-observed acquisition chart with observation-bias caveat.
- Anonymous person-ID drill-through: orders, dates, payments and review/delivery
  context. Distinguish selected-period metrics from lifetime diagnostics.

### Delivery and Seller Performance

- Eligible deliveries, late rate, mean delivery days and source-review mean.
- Customer-state late rates with sample counts in tooltips.
- Seller scorecard: item sales, seller orders, item-subtotal AOV, delivery outcomes,
  reviewed-order mean, denominators and shipping-deadline proxy.
- Category delivery/review comparisons with distinct order-category records.
- Seller drill-through to order participation and deadlines; shared-outcome caveat.
- Tooltips: numerator/denominator, reviewed orders, freight and anomaly flags.

## Desktop acceptance checks

Start with cleared filters and the complete purchase range, with no seller/category
interaction implying an allocation of order payments.

1. Compare cards with Q27 and the baseline/rollup checks in verification_results.json.
2. Compare monthly rows with Q15/Q23/Q24 using identical date attribution.
3. Compare state AOV with Q11, customer types with Q26, RFM contribution with Q32
   and cohort cells with Q31.
4. Compare seller metrics with Q10/Q34 and category delivery with Q35.
5. Test month, state, customer segment, category and seller filters separately.
   Confirm which facts each filter reaches and label any intentional boundary.
6. Check BLANK versus zero, future cohort cells and entity totals. Distinct order
   counts are not sums of category/seller order counts.

The SQL suite proves the backend contract only. Desktop relationships, DAX,
visuals, refresh and interactions remain your manual work. After verification,
save the new .pbix locally, add genuine Olist 2.0 screenshots and update the
README status. Keep historical images clearly labeled Olist 1.0.
