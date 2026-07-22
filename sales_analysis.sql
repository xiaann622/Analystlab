-- ============================================================
-- SALES DATA ANALYSIS PROJECT — Master SQL Script
-- Dataset : Kaggle "Sample Sales Data" (Kyanyoga / AdventureWorks-style)
-- Engine  : PostgreSQL 16
-- Author  : Prepared with Claude
-- ============================================================
-- Run order: this script is self-contained and runs top to
-- bottom in psql. Update the \copy path in Section 1 to point
-- at your local CSV before running.
-- ============================================================

-- ============================================================
-- 01_schema_and_load.sql
-- Sales Data Analysis Project — Schema Setup & Data Load
-- Source: Kaggle "Sample Sales Data" (AdventureWorks-style, Kyanyoga)
-- Target: PostgreSQL
-- ============================================================

-- ------------------------------------------------------------
-- STEP 0: Clean slate
-- ------------------------------------------------------------
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS staging_sales CASCADE;

-- ------------------------------------------------------------
-- STEP 1: Staging table
-- The raw Kaggle CSV is one flat, denormalized table (order +
-- product + customer info all in a single row per order line).
-- We load it as-is first, then normalize it into a proper
-- relational schema (3rd normal form) below.
-- ------------------------------------------------------------
CREATE TABLE staging_sales (
    ordernumber        INTEGER,
    quantityordered    INTEGER,
    priceeach          NUMERIC(10,2),
    orderlinenumber    INTEGER,
    sales              NUMERIC(12,2),
    orderdate          DATE,
    status             VARCHAR(20),
    qtr_id             SMALLINT,
    month_id           SMALLINT,
    year_id            SMALLINT,
    productline        VARCHAR(50),
    msrp               NUMERIC(10,2),
    productcode        VARCHAR(20),
    customername       VARCHAR(100),
    phone              VARCHAR(30),
    addressline1       VARCHAR(100),
    addressline2       VARCHAR(100),
    city               VARCHAR(50),
    state              VARCHAR(50),
    postalcode         VARCHAR(20),
    country            VARCHAR(50),
    territory          VARCHAR(20),
    contactlastname    VARCHAR(50),
    contactfirstname   VARCHAR(50),
    dealsize           VARCHAR(10)
);

-- Load the CSV (run from psql, adjust path as needed).
-- The source file's ORDERDATE is like '2/24/2003 0:00', so we
-- import date as text first and cast, OR simply set datestyle.
\copy staging_sales FROM 'sales_data_clean.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ------------------------------------------------------------
-- STEP 2: Normalized schema (3NF)
-- Grain: one row in staging_sales = one order line item.
-- We split it into 4 related tables:
--   customers   (1 row per unique customer)
--   products    (1 row per unique product)
--   orders      (1 row per unique order/header)
--   order_items (1 row per order line — the fact table)
-- ------------------------------------------------------------

CREATE TABLE customers (
    customer_id       SERIAL PRIMARY KEY,
    customer_name     VARCHAR(100) NOT NULL UNIQUE,
    phone             VARCHAR(30),
    address_line1     VARCHAR(100),
    address_line2     VARCHAR(100),
    city              VARCHAR(50),
    state             VARCHAR(50),
    postal_code       VARCHAR(20),
    country           VARCHAR(50),
    territory         VARCHAR(20),
    contact_first_name VARCHAR(50),
    contact_last_name  VARCHAR(50)
);

CREATE TABLE products (
    product_code   VARCHAR(20) PRIMARY KEY,
    product_line   VARCHAR(50) NOT NULL,
    msrp           NUMERIC(10,2) NOT NULL CHECK (msrp >= 0)
);

CREATE TABLE orders (
    order_number   INTEGER PRIMARY KEY,
    order_date     DATE NOT NULL,
    status         VARCHAR(20) NOT NULL,
    qtr_id         SMALLINT NOT NULL CHECK (qtr_id BETWEEN 1 AND 4),
    month_id       SMALLINT NOT NULL CHECK (month_id BETWEEN 1 AND 12),
    year_id        SMALLINT NOT NULL,
    deal_size      VARCHAR(10) NOT NULL,
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_number       INTEGER NOT NULL REFERENCES orders(order_number),
    order_line_number  SMALLINT NOT NULL,
    product_code       VARCHAR(20) NOT NULL REFERENCES products(product_code),
    quantity_ordered   INTEGER NOT NULL CHECK (quantity_ordered > 0),
    price_each         NUMERIC(10,2) NOT NULL CHECK (price_each >= 0),
    sales              NUMERIC(12,2) NOT NULL CHECK (sales >= 0),
    PRIMARY KEY (order_number, order_line_number)
);

-- ------------------------------------------------------------
-- STEP 3: Populate normalized tables from staging
-- ------------------------------------------------------------

-- 3a. customers (dedupe on customer_name)
INSERT INTO customers (customer_name, phone, address_line1, address_line2,
                        city, state, postal_code, country, territory,
                        contact_first_name, contact_last_name)
SELECT DISTINCT ON (customername)
       customername, phone, addressline1, addressline2,
       city, state, postalcode, country, territory,
       contactfirstname, contactlastname
FROM staging_sales
ORDER BY customername;

-- 3b. products (dedupe on productcode)
INSERT INTO products (product_code, product_line, msrp)
SELECT DISTINCT ON (productcode)
       productcode, productline, msrp
FROM staging_sales
ORDER BY productcode;

-- 3c. orders (dedupe on ordernumber, join to customers for FK)
INSERT INTO orders (order_number, order_date, status, qtr_id, month_id,
                     year_id, deal_size, customer_id)
SELECT DISTINCT ON (s.ordernumber)
       s.ordernumber, s.orderdate, s.status, s.qtr_id, s.month_id,
       s.year_id, s.dealsize, c.customer_id
FROM staging_sales s
JOIN customers c ON c.customer_name = s.customername
ORDER BY s.ordernumber;

-- 3d. order_items (the fact/detail table, grain = order line)
INSERT INTO order_items (order_number, order_line_number, product_code,
                          quantity_ordered, price_each, sales)
SELECT ordernumber, orderlinenumber, productcode,
       quantityordered, priceeach, sales
FROM staging_sales;

-- ------------------------------------------------------------
-- STEP 4: Sanity checks
-- ------------------------------------------------------------
SELECT 'staging_sales' AS table_name, COUNT(*) FROM staging_sales
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

-- staging_sales and order_items should match row-for-row (2,823 rows)
-- customers should equal COUNT(DISTINCT customername)  (92)
-- products should equal COUNT(DISTINCT productcode)     (109)
-- orders should equal COUNT(DISTINCT ordernumber)        (307)
-- ============================================================
-- 02_core_queries.sql
-- Core SQL: SELECT / WHERE / ORDER BY, GROUP BY / HAVING, aggregates
-- ============================================================

-- Q1. List all orders that are still "In Process", most recent first.
SELECT order_number, order_date, status, deal_size
FROM orders
WHERE status = 'In Process'
ORDER BY order_date DESC;

-- Q2. Find all order lines for the 'Classic Cars' product line with a
--     sale value over $3,000, largest sale first.
SELECT oi.order_number, oi.product_code, oi.quantity_ordered,
       oi.price_each, oi.sales
FROM order_items oi
JOIN products p ON p.product_code = oi.product_code
WHERE p.product_line = 'Classic Cars'
  AND oi.sales > 3000
ORDER BY oi.sales DESC;

-- Q3. Total revenue, number of orders, and average order value per year.
SELECT year_id,
       COUNT(*)                       AS num_orders,
       SUM(order_total)               AS total_revenue,
       ROUND(AVG(order_total), 2)     AS avg_order_value
FROM (
    SELECT o.order_number, o.year_id, SUM(oi.sales) AS order_total
    FROM orders o
    JOIN order_items oi ON oi.order_number = o.order_number
    GROUP BY o.order_number, o.year_id
) yearly_orders
GROUP BY year_id
ORDER BY year_id;

-- Q4. Revenue by product line, only lines that generated over $500,000
--     in total sales (GROUP BY + HAVING).
SELECT p.product_line,
       COUNT(DISTINCT oi.order_number) AS num_orders,
       SUM(oi.sales)                   AS total_revenue
FROM order_items oi
JOIN products p ON p.product_code = oi.product_code
GROUP BY p.product_line
HAVING SUM(oi.sales) > 500000
ORDER BY total_revenue DESC;

-- Q5. Countries with more than 10 customers, ordered by customer count.
SELECT country, COUNT(*) AS num_customers
FROM customers
GROUP BY country
HAVING COUNT(*) > 10
ORDER BY num_customers DESC;

-- Q6. Basic aggregate summary: overall revenue, avg sale, min/max sale.
SELECT COUNT(*)                    AS total_order_lines,
       SUM(sales)                  AS total_revenue,
       ROUND(AVG(sales), 2)        AS avg_sale_amount,
       MIN(sales)                  AS min_sale,
       MAX(sales)                  AS max_sale
FROM order_items;
-- ============================================================
-- 03_advanced_queries.sql
-- Advanced SQL: Joins, Subqueries, Window Functions
-- ============================================================

-- Q1. INNER JOIN — every order line with its order header and customer.
SELECT o.order_number, o.order_date, c.customer_name, c.country,
       oi.product_code, oi.quantity_ordered, oi.sales
FROM order_items oi
INNER JOIN orders o    ON o.order_number = oi.order_number
INNER JOIN customers c ON c.customer_id  = o.customer_id
ORDER BY o.order_date
LIMIT 20;

-- Q2. LEFT JOIN — every product, with total units sold (0 if never sold).
--     Demonstrates that a LEFT JOIN preserves the "left" table even when
--     there's no match on the right (here, every product happens to have
--     sold at least once, but the pattern is what matters).
SELECT p.product_code, p.product_line,
       COALESCE(SUM(oi.quantity_ordered), 0) AS total_units_sold
FROM products p
LEFT JOIN order_items oi ON oi.product_code = p.product_code
GROUP BY p.product_code, p.product_line
ORDER BY total_units_sold ASC;

-- Q3. RIGHT JOIN — same idea from the other direction: every order line,
--     with product details from the right-hand table (equivalent to an
--     INNER JOIN here since every order line references a valid product,
--     but written as RIGHT JOIN to demonstrate the syntax explicitly).
SELECT oi.order_number, oi.order_line_number, p.product_line, p.msrp
FROM order_items oi
RIGHT JOIN products p ON p.product_code = oi.product_code
ORDER BY oi.order_number
LIMIT 20;

-- Q4. Multi-table join — revenue by territory and product line together.
SELECT c.territory, p.product_line, SUM(oi.sales) AS revenue
FROM order_items oi
JOIN orders o     ON o.order_number = oi.order_number
JOIN customers c  ON c.customer_id  = o.customer_id
JOIN products p   ON p.product_code = oi.product_code
WHERE c.territory IS NOT NULL
GROUP BY c.territory, p.product_line
ORDER BY c.territory, revenue DESC;

-- Q5. Subquery in WHERE — customers whose total spend exceeds the
--     average total spend across all customers.
SELECT customer_name, total_spend
FROM (
    SELECT c.customer_name, SUM(oi.sales) AS total_spend
    FROM customers c
    JOIN orders o     ON o.customer_id  = c.customer_id
    JOIN order_items oi ON oi.order_number = o.order_number
    GROUP BY c.customer_name
) customer_totals
WHERE total_spend > (
    SELECT AVG(sub.total_spend)
    FROM (
        SELECT SUM(oi2.sales) AS total_spend
        FROM orders o2
        JOIN order_items oi2 ON oi2.order_number = o2.order_number
        GROUP BY o2.customer_id
    ) sub
)
ORDER BY total_spend DESC;

-- Q6. Correlated subquery — each product's revenue vs. its product
--     line's average revenue per product.
SELECT p.product_code, p.product_line,
       (SELECT SUM(oi.sales) FROM order_items oi
        WHERE oi.product_code = p.product_code)          AS product_revenue,
       (SELECT ROUND(AVG(line_totals.rev), 2)
        FROM (
            SELECT SUM(oi2.sales) AS rev
            FROM order_items oi2
            JOIN products p2 ON p2.product_code = oi2.product_code
            WHERE p2.product_line = p.product_line
            GROUP BY oi2.product_code
        ) line_totals)                                     AS line_avg_revenue
FROM products p
ORDER BY p.product_line, product_revenue DESC;

-- Q7. Subquery in FROM — top 5 customers by revenue, with their order count.
SELECT customer_name, num_orders, total_spend
FROM (
    SELECT c.customer_name,
           COUNT(DISTINCT o.order_number) AS num_orders,
           SUM(oi.sales)                  AS total_spend
    FROM customers c
    JOIN orders o       ON o.customer_id    = c.customer_id
    JOIN order_items oi ON oi.order_number  = o.order_number
    GROUP BY c.customer_name
) t
ORDER BY total_spend DESC
LIMIT 5;

-- Q8. Window function — ROW_NUMBER: rank each order line within its
--     order by sale amount (highest first).
SELECT order_number, order_line_number, product_code, sales,
       ROW_NUMBER() OVER (PARTITION BY order_number ORDER BY sales DESC) AS line_rank
FROM order_items
ORDER BY order_number, line_rank
LIMIT 20;

-- Q9. Window function — RANK: rank customers by total revenue,
--     with ties sharing a rank.
SELECT customer_name, total_spend,
       RANK() OVER (ORDER BY total_spend DESC) AS revenue_rank
FROM (
    SELECT c.customer_name, SUM(oi.sales) AS total_spend
    FROM customers c
    JOIN orders o       ON o.customer_id   = c.customer_id
    JOIN order_items oi ON oi.order_number = o.order_number
    GROUP BY c.customer_name
) t
ORDER BY revenue_rank
LIMIT 15;

-- Q10. Window function — running monthly revenue total per year
--      (PARTITION BY + ORDER BY for a cumulative sum).
SELECT year_id, month_id,
       SUM(oi.sales) AS monthly_revenue,
       SUM(SUM(oi.sales)) OVER (
           PARTITION BY year_id ORDER BY month_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total_ytd
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY year_id, month_id
ORDER BY year_id, month_id;

-- Q11. Window function — each order's revenue vs. the customer's own
--      average order value, using AVG() OVER (PARTITION BY ...).
SELECT customer_name, order_number, order_total,
       ROUND(AVG(order_total) OVER (PARTITION BY customer_name), 2) AS customer_avg_order
FROM (
    SELECT c.customer_name, o.order_number, SUM(oi.sales) AS order_total
    FROM customers c
    JOIN orders o       ON o.customer_id   = c.customer_id
    JOIN order_items oi ON oi.order_number = o.order_number
    GROUP BY c.customer_name, o.order_number
) order_totals
ORDER BY customer_name, order_number
LIMIT 20;
-- ============================================================
-- 04_business_questions.sql
-- Business Problem Solving: top products/customers, revenue
-- trends, customer purchasing behavior
-- ============================================================

-- B1. Top 10 products by total revenue.
SELECT p.product_code, p.product_line,
       SUM(oi.sales) AS total_revenue,
       SUM(oi.quantity_ordered) AS total_units
FROM order_items oi
JOIN products p ON p.product_code = oi.product_code
GROUP BY p.product_code, p.product_line
ORDER BY total_revenue DESC
LIMIT 10;

-- B2. Top 10 customers by total revenue.
SELECT c.customer_name, c.country,
       SUM(oi.sales) AS total_revenue,
       COUNT(DISTINCT o.order_number) AS num_orders
FROM customers c
JOIN orders o       ON o.customer_id   = c.customer_id
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY c.customer_name, c.country
ORDER BY total_revenue DESC
LIMIT 10;

-- B3. Revenue trend over time (year + month), with month-over-month
--     percent change using the LAG() window function.
SELECT year_id, month_id,
       SUM(oi.sales) AS monthly_revenue,
       ROUND(
         100.0 * (SUM(oi.sales) - LAG(SUM(oi.sales)) OVER (ORDER BY year_id, month_id))
         / NULLIF(LAG(SUM(oi.sales)) OVER (ORDER BY year_id, month_id), 0)
       , 1) AS pct_change_vs_prev_month
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY year_id, month_id
ORDER BY year_id, month_id;

-- B4. Best-performing product line per year (which line led each year).
SELECT year_id, product_line, total_revenue
FROM (
    SELECT o.year_id, p.product_line,
           SUM(oi.sales) AS total_revenue,
           RANK() OVER (PARTITION BY o.year_id ORDER BY SUM(oi.sales) DESC) AS rnk
    FROM orders o
    JOIN order_items oi ON oi.order_number = o.order_number
    JOIN products p     ON p.product_code  = oi.product_code
    GROUP BY o.year_id, p.product_line
) ranked
WHERE rnk = 1
ORDER BY year_id;

-- B5. Customer purchasing behavior — average order value, order
--     frequency, and days between first and last order per customer.
SELECT c.customer_name,
       COUNT(DISTINCT o.order_number)                       AS num_orders,
       ROUND(SUM(oi.sales) / COUNT(DISTINCT o.order_number), 2) AS avg_order_value,
       MIN(o.order_date)                                     AS first_order,
       MAX(o.order_date)                                     AS last_order,
       (MAX(o.order_date) - MIN(o.order_date))                AS customer_lifespan_days
FROM customers c
JOIN orders o       ON o.customer_id   = c.customer_id
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY c.customer_name
ORDER BY avg_order_value DESC
LIMIT 15;

-- B6. Deal size distribution — how many orders and how much revenue
--     comes from Small vs Medium vs Large deals.
SELECT deal_size,
       COUNT(*) AS num_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM orders
GROUP BY deal_size
ORDER BY num_orders DESC;

-- B7. Order status breakdown — how many orders are Shipped, Cancelled,
--     On Hold, etc., and what share of total revenue each represents.
SELECT o.status,
       COUNT(DISTINCT o.order_number)         AS num_orders,
       SUM(oi.sales)                          AS revenue,
       ROUND(100.0 * SUM(oi.sales) / SUM(SUM(oi.sales)) OVER (), 1) AS pct_of_revenue
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY o.status
ORDER BY revenue DESC;

-- B8. Which country/territory generates the most revenue?
SELECT c.country, c.territory, SUM(oi.sales) AS revenue
FROM customers c
JOIN orders o       ON o.customer_id   = c.customer_id
JOIN order_items oi ON oi.order_number = o.order_number
GROUP BY c.country, c.territory
ORDER BY revenue DESC
LIMIT 10;

-- B9. Repeat vs one-time customers — how many customers ordered more
--     than once, and how much more do they spend on average?
SELECT
    CASE WHEN num_orders > 1 THEN 'Repeat Customer' ELSE 'One-Time Customer' END AS customer_type,
    COUNT(*)                       AS num_customers,
    ROUND(AVG(total_spend), 2)     AS avg_spend_per_customer
FROM (
    SELECT c.customer_id,
           COUNT(DISTINCT o.order_number) AS num_orders,
           SUM(oi.sales)                  AS total_spend
    FROM customers c
    JOIN orders o       ON o.customer_id   = c.customer_id
    JOIN order_items oi ON oi.order_number = o.order_number
    GROUP BY c.customer_id
) t
GROUP BY customer_type;

-- B10. Product lines with the highest average discount off MSRP
--      (i.e., price_each vs msrp — a proxy for discounting pressure).
SELECT p.product_line,
       ROUND(AVG(p.msrp), 2)                                   AS avg_msrp,
       ROUND(AVG(oi.price_each), 2)                             AS avg_actual_price,
       ROUND(100.0 * AVG((p.msrp - oi.price_each) / p.msrp), 1) AS avg_discount_pct
FROM order_items oi
JOIN products p ON p.product_code = oi.product_code
GROUP BY p.product_line
ORDER BY avg_discount_pct DESC;
-- ============================================================
-- 05_optimization.sql
-- Query Optimization: indexing concepts + EXPLAIN ANALYZE
-- ============================================================

-- ------------------------------------------------------------
-- 1. Baseline: check query plan BEFORE adding indexes.
--    This is a common filter (join order_items -> products
--    -> filter product_line) that will do a sequential scan
--    on order_items without an index.
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT o.order_number, SUM(oi.sales) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
JOIN products p     ON p.product_code  = oi.product_code
WHERE p.product_line = 'Classic Cars'
GROUP BY o.order_number
ORDER BY revenue DESC;

-- ------------------------------------------------------------
-- 2. Add indexes on foreign key columns and frequently-filtered
--    columns. Postgres auto-indexes PRIMARY KEY / UNIQUE, but
--    FK columns and WHERE/JOIN/GROUP BY/ORDER BY columns are
--    NOT indexed automatically and are the biggest win here.
-- ------------------------------------------------------------

-- FK lookups
CREATE INDEX idx_orders_customer_id      ON orders(customer_id);
CREATE INDEX idx_order_items_order_num   ON order_items(order_number);
CREATE INDEX idx_order_items_product_cd  ON order_items(product_code);

-- Common filter / group-by columns
CREATE INDEX idx_orders_order_date       ON orders(order_date);
CREATE INDEX idx_orders_status           ON orders(status);
CREATE INDEX idx_orders_year_month       ON orders(year_id, month_id);
CREATE INDEX idx_products_product_line   ON products(product_line);
CREATE INDEX idx_customers_country       ON customers(country);

-- Refresh planner statistics so it uses the new indexes intelligently
ANALYZE orders;
ANALYZE order_items;
ANALYZE products;
ANALYZE customers;

-- ------------------------------------------------------------
-- 3. Re-run the same query AFTER indexing — compare the plan.
--    On a small table like this (2,823 rows) Postgres may still
--    choose a sequential scan (it's genuinely faster below a
--    certain table size), but the indexes matter a great deal
--    as this data grows, and they are essential for the FK
--    joins and WHERE clauses used throughout this project.
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT o.order_number, SUM(oi.sales) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
JOIN products p     ON p.product_code  = oi.product_code
WHERE p.product_line = 'Classic Cars'
GROUP BY o.order_number
ORDER BY revenue DESC;

-- ------------------------------------------------------------
-- 4. Writing clean, readable, efficient SQL — a few concrete
--    do's and don'ts demonstrated side by side.
-- ------------------------------------------------------------

-- (a) DON'T use SELECT * when you only need a few columns —
--     it pulls unnecessary data across the wire and prevents
--     index-only scans.
-- Bad:
--   SELECT * FROM order_items WHERE product_code = 'S18_3232';
-- Good:
SELECT order_number, quantity_ordered, sales
FROM order_items
WHERE product_code = 'S18_3232';

-- (b) DON'T wrap indexed columns in functions in the WHERE
--     clause (it disables index usage). Filter on a range
--     instead of a function of the column.
-- Bad:
--   WHERE EXTRACT(YEAR FROM order_date) = 2004
-- Good:
SELECT order_number, order_date
FROM orders
WHERE order_date >= '2004-01-01' AND order_date < '2005-01-01';

-- (c) DO filter as early as possible and only join tables you
--     actually need — fewer rows flow through subsequent joins.
SELECT o.order_number, oi.sales
FROM orders o
JOIN order_items oi ON oi.order_number = o.order_number
WHERE o.status = 'Cancelled';   -- filter first, small result set

-- (d) DO use EXISTS instead of IN with a subquery when only
--     checking for presence, not comparing values — it can
--     short-circuit as soon as one match is found.
SELECT c.customer_name
FROM customers c
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id AND o.status = 'Disputed'
);

-- ------------------------------------------------------------
-- 5. Inspect index usage/storage (useful sanity check).
-- ------------------------------------------------------------
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
