# Olist E-Commerce Data Analysis

End-to-end data analysis project on the Brazilian Olist e-commerce dataset.
100,000+ orders analyzed using PostgreSQL and Power BI.

---

## Project Overview

Olist is the largest department store in Brazilian marketplaces. This project
analyzes 9 relational tables covering customers, orders, products, sellers,
payments, and reviews to extract actionable business insights.

Questions answered:
- Which product categories generate the most revenue?
- How do delivery delays affect customer review scores?
- Which states have the most orders and best customer satisfaction?
- How has order volume grown month over month?
- What payment methods do customers prefer?

---

## Repository Structure

```
olist-ecommerce-analysis/
│
├── sql/
│   └── olist_queries.sql        
│
├── dashboard/
│   └── olist_dashboard.pbix     
│
├── images/
│   ├── overview_page.jpg        
│   └── deep_dive_page.jpg       
│
└── README.md
```

---

## Dataset

Source: [Olist Brazilian E-Commerce — Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

| Table | Rows | Description |
|---|---|---|
| customers | 99,441 | Customer info and location |
| orders | 99,441 | Order status and timestamps |
| order_items | 112,650 | Items within each order |
| order_payments | 103,886 | Payment details per order |
| order_reviews | 99,224 | Customer review scores and comments |
| products | 32,951 | Product details and category |
| sellers | 3,095 | Seller info and location |
| geolocation | 1,000,163 | Zip code to lat/lng mapping |
| cat_trans | 71 | Portuguese to English category translation |

---

## Tools

| Tool | Purpose |
|---|---|
| PostgreSQL 18 + pgAdmin 4 | Database setup and SQL analysis |
| Power BI Desktop | Dashboard and visualizations |

---

## Dashboard

### Overview Page
KPI cards, revenue by category, monthly order trend.

![Overview](images/overview_page.jpg)

Key numbers:
- Total Revenue: 16.01M BRL
- Total Orders: 99,441
- Avg Review Score: 4.09 / 5
- Avg Delivery Time: 12.5 days

---

### Deep Dive Page
Payment breakdown, top 10 sellers, review scores by state, orders by state.

![Deep Dive](images/deep_dive_page.jpg)

---

## Key Business Insights

### 1. Delivery delays directly hurt review scores
Orders delivered early or on time average a review score of 4.2+, while orders
delayed by 7+ days drop to 2.5 or below. Logistics performance is the biggest
driver of customer satisfaction in this dataset, not product quality. Olist
should implement delivery delay alerts for sellers and focus on improving
last-mile logistics in states with the worst average delays.

### 2. Sao Paulo dominates but creates concentration risk
SP accounts for 40,000+ orders — nearly 4x more than RJ in second place. Over
40% of all revenue comes from a single state. Any logistics disruption in SP
would severely impact the entire business. Olist should invest in growing its
seller and customer base in MG, RS, and PR to reduce this geographic dependency.

### 3. Credit card dominates but boleto shows financial inclusion
78.34% of payments are credit card, but boleto accounts for 17.92% (2.87M BRL).
Boleto is used by customers who cannot access credit — this is not a small
segment. Olist should protect and expand boleto support as a strategic advantage
for reaching Brazil's unbanked population.

---

## SQL Analysis

29 queries written across 3 difficulty levels: beginner, intermediate, advanced.

Sample — intermediate (multi-table join):
```sql
-- total revenue per product category
SELECT ct.category_english,
ROUND(SUM(oi.price)::NUMERIC, 2) AS total_revenue,
COUNT(DISTINCT oi.order_id) AS total_orders
FROM order_items oi
JOIN products p ON oi.prod_id = p.prod_id
JOIN cat_trans ct ON p.category = ct.category
GROUP BY ct.category_english
ORDER BY total_revenue DESC LIMIT 15;
```

Sample — advanced (CTE + window function):
```sql
-- month-over-month revenue growth
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.purchase_time) AS month,
        ROUND(SUM(op.pay_value)::NUMERIC, 2) AS revenue
    FROM orders o
    JOIN order_payments op ON o.order_id = op.order_id
    GROUP BY DATE_TRUNC('month', o.purchase_time)
)
SELECT month, revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month) * 100, 2) AS growth_pct
FROM monthly ORDER BY month;
```

Full query file: [sql/olist_queries.sql](sql/olist_queries.sql)

---

## How to Run

**PostgreSQL setup:**
1. Download the dataset from Kaggle
2. Create a database called `olist` in pgAdmin
3. Run the CREATE TABLE statements
4. Import each CSV using pgAdmin Table Import Wizard
5. Run queries from `sql/olist_queries.sql`

**Power BI:**
1. Open `dashboard/olist_dashboard.pbix`
2. Update the PostgreSQL connection under Home → Transform Data → Data Source Settings
3. Refresh the data

---

## Author

Purav Desai
B.Tech IT — Semester 6 | SCET, Surat

GitHub: [PuravDesai004](https://github.com/PuravDesai004)
LinkedIn: [www.linkedin.com/in/puravdesai41]
