-- ============================================================
-- olist dataset analysis — sql queries
-- author: purav desai | scet surat | b.tech it
-- database: postgresql | db: olist
-- total queries: 29 (8 beginner + 15 intermediate + 6 advanced)
-- ============================================================


-- ============================================================
-- beginner — single table, group by, basic filters
-- ============================================================

-- 1 orders by status
SELECT status, COUNT(*) AS total_orders
FROM orders
GROUP BY status
ORDER BY total_orders DESC;


-- 2 top 5 cities by customers
SELECT city, COUNT(*) AS total
FROM customers
GROUP BY city
ORDER BY total DESC LIMIT 5;


-- 3 revenue by payment type
SELECT pay_type, COUNT(*) AS transactions,
ROUND(SUM(pay_value)::NUMERIC, 2) AS total_revenue
FROM order_payments
GROUP BY pay_type
ORDER BY total_revenue DESC;


-- 4. review score distribution
SELECT score, COUNT(*) AS total,
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM order_reviews
GROUP BY score
ORDER BY score;


-- 5 seller count by state
SELECT state, COUNT(*) AS total_sellers
FROM sellers
GROUP BY state
ORDER BY total_sellers DESC;


-- 6 orders not delivered
SELECT status, COUNT(*) AS total
FROM orders
WHERE status != 'delivered'
GROUP BY status
ORDER BY total DESC;


-- 7 avg installments by payment type
SELECT pay_type,
ROUND(AVG(installments)::NUMERIC, 2) AS avg_installments,
MAX(installments) AS max_installments
FROM order_payments
GROUP BY pay_type
ORDER BY avg_installments DESC;


-- 8 total orders and revenue by year
SELECT EXTRACT(YEAR FROM purchase_time) AS year,
COUNT(*) AS total_orders,
ROUND(SUM(op.pay_value)::NUMERIC, 2) AS total_revenue
FROM orders o
JOIN order_payments op ON o.order_id = op.order_id
GROUP BY EXTRACT(YEAR FROM purchase_time)
ORDER BY year;


-- ============================================================
-- intermediate — joins, having, multi-table
-- ============================================================

-- 1 top 10 expensive categories
SELECT p.category,
ROUND(AVG(oi.price)::NUMERIC, 2) AS avg_price
FROM order_items oi
JOIN products p ON oi.prod_id = p.prod_id
GROUP BY p.category
ORDER BY avg_price DESC LIMIT 10;


-- 2 total revenue per product category (english names)
SELECT ct.category_english,
ROUND(SUM(oi.price)::NUMERIC, 2) AS total_revenue,
COUNT(DISTINCT oi.order_id) AS total_orders
FROM order_items oi
JOIN products p ON oi.prod_id = p.prod_id
JOIN cat_trans ct ON p.category = ct.category
GROUP BY ct.category_english
ORDER BY total_revenue DESC LIMIT 15;


-- 3 top 10 sellers by number of orders
SELECT oi.seller_id, s.city, s.state,
COUNT(DISTINCT oi.order_id) AS total_orders,
ROUND(SUM(oi.price)::NUMERIC, 2) AS total_revenue
FROM order_items oi
JOIN sellers s ON oi.seller_id = s.seller_id
GROUP BY oi.seller_id, s.city, s.state
ORDER BY total_orders DESC LIMIT 10;


-- 4 average order value by customer state
SELECT c.state,
COUNT(DISTINCT o.order_id) AS total_orders,
ROUND(AVG(op.pay_value)::NUMERIC, 2) AS avg_order_value,
ROUND(SUM(op.pay_value)::NUMERIC, 2) AS total_spent
FROM customers c
JOIN orders o ON c.cust_id = o.cust_id
JOIN order_payments op ON o.order_id = op.order_id
GROUP BY c.state
ORDER BY total_spent DESC;


-- 5 count of orders per status with percentage
SELECT status, COUNT(*) AS total,
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM orders
GROUP BY status
ORDER BY total DESC;


-- 6 revenue by payment type with percentage
SELECT pay_type, COUNT(*) AS transactions,
ROUND(SUM(pay_value)::NUMERIC, 2) AS total_revenue,
ROUND(AVG(pay_value)::NUMERIC, 2) AS avg_payment,
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM order_payments
GROUP BY pay_type
ORDER BY total_revenue DESC;


-- 7 avg freight vs price by category
SELECT ct.category_english,
ROUND(AVG(oi.price)::NUMERIC, 2) AS avg_price,
ROUND(AVG(oi.freight)::NUMERIC, 2) AS avg_freight,
ROUND((AVG(oi.freight) * 100.0 / AVG(oi.price))::NUMERIC, 2) AS freight_pct
FROM order_items oi
JOIN products p ON oi.prod_id = p.prod_id
JOIN cat_trans ct ON p.category = ct.category
GROUP BY ct.category_english
ORDER BY freight_pct DESC LIMIT 15;


-- 8 orders with more than 3 items
SELECT order_id, COUNT(item_id) AS item_count,
ROUND(SUM(price)::NUMERIC, 2) AS order_total
FROM order_items
GROUP BY order_id
HAVING COUNT(item_id) > 3
ORDER BY item_count DESC;


-- 9 customers who placed more than 1 order
SELECT c.cust_id, c.city, c.state,
COUNT(o.order_id) AS order_count,
ROUND(SUM(op.pay_value)::NUMERIC, 2) AS total_spent
FROM customers c
JOIN orders o ON c.cust_id = o.cust_id
JOIN order_payments op ON o.order_id = op.order_id
GROUP BY c.cust_id, c.city, c.state
HAVING COUNT(o.order_id) > 1
ORDER BY order_count DESC;


-- 10 monthly order count and revenue trend
SELECT DATE_TRUNC('month', purchase_time) AS month,
COUNT(*) AS order_count,
ROUND(SUM(op.pay_value)::NUMERIC, 2) AS monthly_revenue
FROM orders o
JOIN order_payments op ON o.order_id = op.order_id
GROUP BY DATE_TRUNC('month', purchase_time)
ORDER BY month;


-- 11 top 5 categories by avg review score
SELECT ct.category_english,
ROUND(AVG(r.score)::NUMERIC, 2) AS avg_score,
COUNT(r.review_id) AS total_reviews
FROM order_reviews r
JOIN order_items oi ON r.order_id = oi.order_id
JOIN products p ON oi.prod_id = p.prod_id
JOIN cat_trans ct ON p.category = ct.category
GROUP BY ct.category_english
HAVING COUNT(r.review_id) > 100
ORDER BY avg_score DESC LIMIT 5;


-- 12 delivery delay in days per order
SELECT order_id,
EXTRACT(DAY FROM delivered_date - purchase_time) AS delivery_days,
EXTRACT(DAY FROM estimated_date - purchase_time) AS estimated_days,
EXTRACT(DAY FROM delivered_date - estimated_date) AS delay_days
FROM orders
WHERE delivered_date IS NOT NULL LIMIT 20;


-- 13 avg delivery delay by customer state
SELECT c.state,
ROUND(AVG(EXTRACT(DAY FROM o.delivered_date - o.estimated_date))::NUMERIC, 2) AS avg_delay_days
FROM orders o
JOIN customers c ON o.cust_id = c.cust_id
WHERE o.delivered_date IS NOT NULL
GROUP BY c.state
ORDER BY avg_delay_days DESC;


-- 14 products never ordered
SELECT p.prod_id, p.category
FROM products p
LEFT JOIN order_items oi ON p.prod_id = oi.prod_id
WHERE oi.prod_id IS NULL;


-- 15 correlation between delay and review score
SELECT
CASE
    WHEN EXTRACT(DAY FROM o.delivered_date - o.estimated_date) < 0 THEN 'early'
    WHEN EXTRACT(DAY FROM o.delivered_date - o.estimated_date) = 0 THEN 'on time'
    WHEN EXTRACT(DAY FROM o.delivered_date - o.estimated_date) <= 7 THEN 'late 1-7 days'
    ELSE 'late 7+ days'
END AS delivery_status,
ROUND(AVG(r.score)::NUMERIC, 2) AS avg_review,
COUNT(*) AS total_orders
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.delivered_date IS NOT NULL
GROUP BY delivery_status
ORDER BY avg_review DESC;


-- ============================================================
-- advanced — ctes, window functions, subqueries
-- ============================================================

-- 1 rfm segmentation per customer
WITH rfm AS (
    SELECT o.cust_id,
        MAX(o.purchase_time) AS last_order,
        COUNT(o.order_id) AS frequency,
        ROUND(SUM(op.pay_value)::NUMERIC, 2) AS monetary
    FROM orders o
    JOIN order_payments op ON o.order_id = op.order_id
    GROUP BY o.cust_id
)
SELECT cust_id,
    CURRENT_DATE - last_order::DATE AS recency_days,
    frequency, monetary
FROM rfm
ORDER BY monetary DESC LIMIT 20;


-- 2 rank sellers by monthly revenue
SELECT oi.seller_id,
    DATE_TRUNC('month', o.purchase_time) AS month,
    ROUND(SUM(oi.price)::NUMERIC, 2) AS revenue,
    RANK() OVER (
        PARTITION BY DATE_TRUNC('month', o.purchase_time)
        ORDER BY SUM(oi.price) DESC
    ) AS rank_in_month
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY oi.seller_id, DATE_TRUNC('month', o.purchase_time)
ORDER BY month, rank_in_month LIMIT 30;


-- 3 month-over-month revenue growth using lag()
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.purchase_time) AS month,
        ROUND(SUM(op.pay_value)::NUMERIC, 2) AS revenue
    FROM orders o
    JOIN order_payments op ON o.order_id = op.order_id
    GROUP BY DATE_TRUNC('month', o.purchase_time)
)
SELECT month, revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month) * 100, 2) AS growth_pct
FROM monthly
ORDER BY month;


-- 4 running total of orders each month
SELECT DATE_TRUNC('month', purchase_time) AS month,
    COUNT(*) AS orders_this_month,
    SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', purchase_time)) AS running_total
FROM orders
GROUP BY DATE_TRUNC('month', purchase_time)
ORDER BY month;


-- 5 top 3 products per category by total sales
WITH ranked AS (
    SELECT ct.category_english, oi.prod_id,
        ROUND(SUM(oi.price)::NUMERIC, 2) AS total_sales,
        ROW_NUMBER() OVER (
            PARTITION BY ct.category_english
            ORDER BY SUM(oi.price) DESC
        ) AS rank_in_cat
    FROM order_items oi
    JOIN products p ON oi.prod_id = p.prod_id
    JOIN cat_trans ct ON p.category = ct.category
    GROUP BY ct.category_english, oi.prod_id
)
SELECT * FROM ranked
WHERE rank_in_cat <= 3
ORDER BY category_english, rank_in_cat;


-- 6 flag customers as repeat or one-time
SELECT cust_id, total_orders,
    CASE WHEN total_orders > 1 THEN 'repeat'
         ELSE 'one-time' END AS customer_type
FROM (
    SELECT cust_id, COUNT(order_id) AS total_orders
    FROM orders GROUP BY cust_id
) AS t
ORDER BY total_orders DESC LIMIT 15;
