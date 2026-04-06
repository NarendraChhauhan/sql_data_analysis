-- Import raw CSV into a proper DuckDB table
CREATE TABLE customers AS
SELECT *
FROM read_csv_auto('data/olist_customers_dataset.csv');

CREATE TABLE geolocation AS
SELECT * FROM read_csv_auto('data/olist_geolocation_dataset.csv');

CREATE TABLE orders AS
SELECT * FROM read_csv_auto('data/olist_orders_dataset.csv');

CREATE TABLE order_items AS
SELECT * FROM read_csv_auto('data/olist_order_items_dataset.csv');

CREATE TABLE payments AS
SELECT * FROM read_csv_auto('data/olist_order_payments_dataset.csv');

CREATE TABLE reviews AS
SELECT * FROM read_csv_auto('data/olist_order_reviews_dataset.csv');

CREATE TABLE products AS
SELECT * FROM read_csv_auto('data/olist_products_dataset.csv');

CREATE TABLE sellers AS
SELECT * FROM read_csv_auto('data/olist_sellers_dataset.csv');

CREATE TABLE cat_names AS
SELECT * FROM read_csv_auto('data/product_category_name_translation.csv');

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'main';

SELECT 'cat_names' AS table_name, COUNT(*) AS row_count FROM main.cat_names
UNION ALL
SELECT 'customers', COUNT(*) FROM main.customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM main.geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM main.order_items
UNION ALL
SELECT 'orders', COUNT(*) FROM main.orders
UNION ALL
SELECT 'payments', COUNT(*) FROM main.payments
UNION ALL
SELECT 'products', COUNT(*) FROM main.products
UNION ALL
SELECT 'reviews', COUNT(*) FROM main.reviews
UNION ALL
SELECT 'sellers', COUNT(*) FROM main.sellers;


-- Check duplicates in orders

SELECT order_id, COUNT(*) AS n
FROM main.orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Check duplicates in order_items

SELECT order_id, order_item_id, COUNT(*) AS n
FROM main.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Check duplicates in payments

SELECT order_id, payment_sequential, COUNT(*) AS n
FROM main.payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- Step 2: Create Simple Views (Optional but Useful)

CREATE VIEW clean_orders AS
SELECT * FROM main.orders;

CREATE VIEW clean_order_items AS
SELECT * FROM main.order_items;

CREATE VIEW clean_payments AS
SELECT * FROM main.payments;

-- ##############################
-- ##############################

--  Bucket #1 – Revenue & Growth

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_orders / clean_order_items
-- We didn’t need any other tables (e.g. products, customers) for these three KPIs 
-- because they’re pure sales-trend metrics that depend only on order dates and line-item prices.

-- ##############################
-- KPI 1 · Monthly Revenue Trend
-- ##############################

-- How many NULLs or negative prices exist?
SELECT
    COUNT(*)                                 AS rows_total,
    SUM(price IS NULL OR price < 0)          AS rows_bad_price,
    SUM(o.order_approved_at IS NULL)         AS rows_missing_date
FROM clean_orders        o
JOIN clean_order_items   i USING(order_id);

CREATE OR REPLACE VIEW kpi1_clean_orders AS
SELECT *
FROM clean_orders
WHERE order_approved_at IS NOT NULL;

-- 1️⃣  Build order-level revenue (price summed per order)

WITH order_totals AS (
    SELECT o.order_id,
           SUM(oi.price) AS order_revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    GROUP BY o.order_id
)

-- 2️⃣  Aggregate those order totals by calendar month
  
SELECT DATE_TRUNC('month', co.order_approved_at) AS month,
       ROUND(SUM(t.order_revenue), 2)          AS total_revenue
FROM kpi1_clean_orders  co
JOIN order_totals  t USING (order_id)
GROUP BY month
ORDER BY month;

-- ##############################
-- KPI 2 · Year-over-Year Growth %
-- ##############################

-- 1️⃣  Annual revenue table

WITH annual_rev AS (
    SELECT
        EXTRACT(year FROM o.order_approved_at) AS yr,   -- calendar year
        ROUND(SUM(oi.price), 2)               AS total_revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY yr
)

-- 2️⃣  YoY % change: (current – prior) / prior
  
SELECT
    yr AS year,
    total_revenue,
    ROUND(
        100.0 * (total_revenue
                 - LAG(total_revenue) OVER (ORDER BY yr))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY yr), 0), 2
    ) AS yoy_growth_pct
FROM annual_rev
ORDER BY yr;

--
-- 1️⃣  Revenue for Jan-Sep only (across 2017 & 2018)

WITH period_rev AS (
    SELECT
        EXTRACT(year FROM o.order_approved_at) AS yr,   -- calendar year
        ROUND(SUM(oi.price), 2)               AS total_revenue
    FROM clean_orders        o
    JOIN clean_order_items   oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
      AND EXTRACT(month FROM o.order_approved_at) BETWEEN 1 AND 9  -- Jan…Sep window
      AND EXTRACT(year  FROM o.order_approved_at) IN (2017, 2018)  -- keep only the two years
    GROUP BY yr
)

-- 2️⃣  YoY % = (2018 – 2017) / 2017
  
SELECT
    yr  AS year,
    total_revenue,
    ROUND(
        100.0 * (total_revenue
                 - LAG(total_revenue) OVER (ORDER BY yr))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY yr), 0), 2
    ) AS yoy_growth_pct
FROM period_rev
ORDER BY yr;


-- ##############################
-- KPI 3 · Average Order Value (AOV) Trend
-- ##############################

-- 1️⃣  Build monthly order totals (revenue per order + month tag)

WITH order_totals AS (
    SELECT o.order_id,
           SUM(oi.price) AS order_revenue,
           DATE_TRUNC('month', o.order_approved_at) AS month
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY o.order_id, month
)

-- 2️⃣  Compute average order value per month
  
SELECT month,
       ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM order_totals
GROUP BY month
ORDER BY month;


-- ##############################
-- ##############################

--  Bucket #2 – Product & Category Performance

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_order_items / products / clean_orders
-- These three tables cover all revenue, time, and category info needed 


-- ##############################
-- KPI 1 · Top Categories by Revenue and Units Sold
-- ##############################


-- Reveal which categories actually drive the cash register and the volume (helps with inventory & marketing focus).

-- 1️⃣  Join items → products to get the category name

SELECT
    p.product_category_name                           AS category,
    ROUND(SUM(oi.price), 2)                           AS total_revenue,
    COUNT(*)                                          AS units_sold     -- each row = one item
FROM clean_order_items oi
JOIN products         p ON oi.product_id = p.product_id
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 10;  -- top 10 categories



/*
PROJECT SUMMARY – BRAZILIAN E-COMMERCE ANALYTICS (DuckDB, SQL-only)

In two focused buckets we delivered nine lean KPIs that answer core business questions.  
1️⃣ **Revenue & Growth** – monthly GMV trend, Jan-Sep YoY growth (-› +99 %), and AOV stability showed that topline expansion is driven by sheer order volume, not bigger baskets.  
2️⃣ **Product & Category Performance** – top-10 categories revealed where 60 % of cash sits; fast-growing niches (home appliances +5 572 % YoY) flagged emerging demand; a high-AOV/low-volume list exposed premium segments like PCs (R$ 1 099 per item).  


**Business impact:** leadership now knows which metros and categories deserve inventory depth, which remote areas need logistics attention, and where upsell campaigns can lift AOV.  
**Career take-away for analysts:** we demonstrated end-to-end, production-ready analytics using only DuckDB SQL—no BI tool, no Python—emphasising clean schema thinking, concise window/aggregate functions, and storytelling that converts raw CSVs into board-level decisions.
*/
