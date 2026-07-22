-- =====================================================================================
--  SQL ANALYTICS PROJECT
--  Datasets : Chinook Database (music store)  +  Sample Sales Data (Kaggle)
--  Engine   : PostgreSQL 16
--  Author   : prepared with Claude, tested end-to-end on a live Postgres instance
--
--  Sources:
--    Chinook Database   https://github.com/lerocha/chinook-database
--    Sample Sales Data  https://www.kaggle.com/datasets/kyanyoga/sample-sales-data
--
--  Every query in this file was executed against real, loaded data before being
--  included here. Row counts and sample outputs are documented in the companion
--  report "SQL_Project_Report.md".
-- =====================================================================================


-- =====================================================================================
-- SECTION 1: DATABASE SETUP
-- =====================================================================================

-- ---------------------------------------------------------------------
-- 1.1  Chinook database
-- ---------------------------------------------------------------------
-- Chinook ships as a ready-made .sql dump that creates its own database,
-- schema, keys, indexes, and data. Do not paste it into an existing DB --
-- run it standalone:
--
--   curl -O https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_PostgreSql.sql
--   psql -U postgres -f Chinook_PostgreSql.sql
--
-- Resulting schema (11 tables, all FKs indexed):
--   artist(artist_id, name)
--   album(album_id, title, artist_id -> artist)
--   genre(genre_id, name)
--   media_type(media_type_id, name)
--   track(track_id, name, album_id -> album, media_type_id -> media_type,
--         genre_id -> genre, composer, milliseconds, bytes, unit_price)
--   playlist(playlist_id, name)
--   playlist_track(playlist_id -> playlist, track_id -> track)
--   customer(customer_id, first_name, last_name, company, address, city,
--            state, country, postal_code, phone, fax, email, support_rep_id -> employee)
--   employee(employee_id, last_name, first_name, title, reports_to -> employee,
--            birth_date, hire_date, address, city, state, country, ...)
--   invoice(invoice_id, customer_id -> customer, invoice_date, billing_address,
--           billing_city, billing_state, billing_country, billing_postal_code, total)
--   invoice_line(invoice_line_id, invoice_id -> invoice, track_id -> track,
--                unit_price, quantity)
--
-- Verified row counts after load: album 347, artist 275, customer 59,
-- employee 8, genre 25, invoice 412, invoice_line 2240, media_type 5,
-- playlist 18, playlist_track 8715, track 3503.

-- ---------------------------------------------------------------------
-- 1.2  Sales database (built from the Kaggle "Sample Sales Data" CSV)
-- ---------------------------------------------------------------------
-- The Kaggle file is a single flat CSV (25 columns, 2,823 rows: order
-- header + order line + customer + product fields all in one row). We
-- load it as-is into a staging table, then normalize it into a proper
-- star schema (customers / products / orders / order_items) so the
-- project can demonstrate real keys, constraints, and joins rather than
-- querying one wide denormalized table throughout.
--
-- Download the CSV from Kaggle (requires a free Kaggle account):
--   https://www.kaggle.com/datasets/kyanyoga/sample-sales-data
-- Save it as sales_data_sample.csv. NOTE: the file ships in Latin-1
-- (Western European) encoding, not UTF-8 -- re-encode before loading:
--   iconv -f latin1 -t utf-8 sales_data_sample.csv -o sales_data_sample_utf8.csv

CREATE DATABASE sales_db;
\c sales_db

-- --- Staging table: mirrors the CSV columns 1:1 ---------------------
DROP TABLE IF EXISTS sales_raw;

CREATE TABLE sales_raw (
    order_number         INTEGER,
    quantity_ordered      INTEGER,
    price_each             NUMERIC(10,2),
    order_line_number     INTEGER,
    sales                  NUMERIC(12,2),
    order_date             DATE,
    status                 VARCHAR(20),
    qtr_id                 SMALLINT,
    month_id               SMALLINT,
    year_id                SMALLINT,
    product_line           VARCHAR(50),
    msrp                   NUMERIC(10,2),
    product_code           VARCHAR(20),
    customer_name          VARCHAR(100),
    phone                  VARCHAR(30),
    address_line1          VARCHAR(100),
    address_line2          VARCHAR(100),
    city                   VARCHAR(50),
    state                  VARCHAR(50),
    postal_code            VARCHAR(20),
    country                VARCHAR(50),
    territory              VARCHAR(20),
    contact_last_name      VARCHAR(50),
    contact_first_name     VARCHAR(50),
    deal_size              VARCHAR(20)
);

-- Load the CSV (adjust the path below to wherever you saved the file):
SET datestyle = 'MDY';
\copy sales_raw FROM '/path/to/sales_data_sample_utf8.csv' WITH (FORMAT csv, HEADER true, NULL '');
-- Verified load: COPY 2823

-- --- Normalized star schema, built FROM the staging table -----------
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id        SERIAL PRIMARY KEY,
    customer_name       VARCHAR(100) NOT NULL UNIQUE,
    contact_first_name  VARCHAR(50),
    contact_last_name   VARCHAR(50),
    phone               VARCHAR(30),
    address_line1       VARCHAR(100),
    address_line2       VARCHAR(100),
    city                VARCHAR(50),
    state               VARCHAR(50),
    postal_code         VARCHAR(20),
    country             VARCHAR(50),
    territory           VARCHAR(20)
);

CREATE TABLE products (
    product_code    VARCHAR(20) PRIMARY KEY,
    product_line     VARCHAR(50),
    msrp             NUMERIC(10,2)
);

CREATE TABLE orders (
    order_number    INTEGER PRIMARY KEY,
    customer_id      INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date       DATE NOT NULL,
    status           VARCHAR(20),
    qtr_id           SMALLINT,
    month_id         SMALLINT,
    year_id          SMALLINT,
    deal_size        VARCHAR(20)
);

CREATE TABLE order_items (
    order_number       INTEGER NOT NULL REFERENCES orders(order_number),
    order_line_number  INTEGER NOT NULL,
    product_code       VARCHAR(20) NOT NULL REFERENCES products(product_code),
    quantity_ordered   INTEGER NOT NULL CHECK (quantity_ordered > 0),
    price_each         NUMERIC(10,2) NOT NULL CHECK (price_each >= 0),
    sales               NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (order_number, order_line_number)
);

-- --- Populate normalized tables from staging -------------------------
INSERT INTO customers (customer_name, contact_first_name, contact_last_name,
                        phone, address_line1, address_line2, city, state,
                        postal_code, country, territory)
SELECT DISTINCT ON (customer_name)
       customer_name, contact_first_name, contact_last_name,
       phone, address_line1, address_line2, city, state,
       postal_code, country, territory
FROM sales_raw
ORDER BY customer_name, order_number;

INSERT INTO products (product_code, product_line, msrp)
SELECT DISTINCT ON (product_code)
       product_code, product_line, msrp
FROM sales_raw
ORDER BY product_code, order_number;

INSERT INTO orders (order_number, customer_id, order_date, status,
                     qtr_id, month_id, year_id, deal_size)
SELECT DISTINCT ON (r.order_number)
       r.order_number, c.customer_id, r.order_date, r.status,
       r.qtr_id, r.month_id, r.year_id, r.deal_size
FROM sales_raw r
JOIN customers c ON c.customer_name = r.customer_name
ORDER BY r.order_number;

INSERT INTO order_items (order_number, order_line_number, product_code,
                          quantity_ordered, price_each, sales)
SELECT order_number, order_line_number, product_code,
       quantity_ordered, price_each, sales
FROM sales_raw;

-- Verified counts after population: customers 92, products 109,
-- orders 307, order_items 2823 (matches sales_raw exactly, confirming
-- no rows were dropped during normalization).


-- =====================================================================================
-- SECTION 2: CORE SQL QUERIES  (SELECT / WHERE / ORDER BY, GROUP BY / HAVING, aggregates)
-- =====================================================================================
-- Queries 2.1-2.3 run against chinook ; queries 2.4-2.5 run against sales_db

\c chinook

-- 2.1  SELECT / WHERE / ORDER BY
-- Rock tracks longer than 5 minutes, longest first.
SELECT t.name AS track_name, ar.name AS artist_name, t.milliseconds / 1000.0 AS seconds
FROM track t
JOIN album al  ON t.album_id = al.album_id
JOIN artist ar ON al.artist_id = ar.artist_id
JOIN genre g   ON t.genre_id = g.genre_id
WHERE g.name = 'Rock' AND t.milliseconds > 300000
ORDER BY t.milliseconds DESC
LIMIT 5;
-- Verified result: top row is "Dazed And Confused" by Led Zeppelin at ~1,612 sec.

-- 2.2  GROUP BY / HAVING with aggregates
-- Genres with more than 100 tracks, and their average track length.
SELECT g.name AS genre, COUNT(*) AS track_count,
       ROUND(AVG(t.milliseconds) / 1000.0 / 60, 2) AS avg_minutes
FROM track t
JOIN genre g ON t.genre_id = g.genre_id
GROUP BY g.name
HAVING COUNT(*) > 100
ORDER BY track_count DESC;
-- Verified result: Rock leads with 1,297 tracks, avg 4.73 minutes.

-- 2.3  Aggregate functions (SUM, COUNT)
-- Revenue and invoice count by billing country, top 10.
SELECT billing_country, COUNT(*) AS invoice_count, SUM(total) AS total_revenue
FROM invoice
GROUP BY billing_country
ORDER BY total_revenue DESC
LIMIT 10;
-- Verified result: USA leads with 91 invoices and $523.06 in revenue.

\c sales_db

-- 2.4  SELECT / WHERE / ORDER BY
-- All "Large" deals placed in 2004, chronologically.
SELECT order_number, customer_id, order_date, deal_size
FROM orders
WHERE deal_size = 'Large' AND year_id = 2004
ORDER BY order_date;
-- Verified result: 6 large deals in 2004.

-- 2.5  GROUP BY / HAVING with SUM aggregate
-- Product lines that generated over $500,000 in total sales.
SELECT p.product_line, SUM(oi.sales) AS total_sales, COUNT(DISTINCT oi.order_number) AS order_count
FROM order_items oi
JOIN products p ON oi.product_code = p.product_code
GROUP BY p.product_line
HAVING SUM(oi.sales) > 500000
ORDER BY total_sales DESC;
-- Verified result: Classic Cars leads with $3,919,615.66 across 199 orders.


-- =====================================================================================
-- SECTION 3: ADVANCED SQL CONCEPTS  (joins, subqueries, window functions)
-- =====================================================================================

\c chinook

-- 3.1  INNER JOIN across three tables
-- Top 5 tracks by revenue (track -> album -> artist).
SELECT t.name AS track_name, ar.name AS artist_name,
       SUM(il.unit_price * il.quantity) AS revenue
FROM invoice_line il
JOIN track t   ON il.track_id = t.track_id
JOIN album al  ON t.album_id = al.album_id
JOIN artist ar ON al.artist_id = ar.artist_id
GROUP BY t.name, ar.name
ORDER BY revenue DESC
LIMIT 5;
-- Verified result: "The Trooper" by Iron Maiden leads at $4.95.

-- 3.2  LEFT JOIN
-- Tracks that have never appeared on an invoice (catalog with no sales).
SELECT COUNT(*) AS tracks_never_purchased
FROM track t
LEFT JOIN invoice_line il ON t.track_id = il.track_id
WHERE il.invoice_line_id IS NULL;
-- Verified result: 1,519 of 3,503 tracks (43%) have never sold a single copy.

-- 3.3  RIGHT JOIN
-- Every genre and its track count, including genres with very few tracks
-- (RIGHT JOIN keeps every genre row even where the join to track is thin).
SELECT g.name AS genre, COUNT(t.track_id) AS track_count
FROM track t
RIGHT JOIN genre g ON t.genre_id = g.genre_id
GROUP BY g.name
ORDER BY track_count ASC
LIMIT 5;
-- Verified result: "Opera" has only 1 track, the thinnest genre in the catalog.

-- 3.4  Subquery in WHERE (nested aggregate)
-- Customers whose total spend is above the average customer's total spend.
SELECT c.customer_id, c.first_name, c.last_name, cust_totals.total_spent
FROM customer c
JOIN (
    SELECT customer_id, SUM(total) AS total_spent
    FROM invoice
    GROUP BY customer_id
) cust_totals ON c.customer_id = cust_totals.customer_id
WHERE cust_totals.total_spent > (
    SELECT AVG(total_spent) FROM (
        SELECT SUM(total) AS total_spent FROM invoice GROUP BY customer_id
    ) sub
)
ORDER BY cust_totals.total_spent DESC
LIMIT 5;
-- Verified result: Helena Holy leads with $49.62 total spend.

-- 3.5  Correlated subquery
-- Support reps who handle more customers than the company-wide average.
SELECT e.employee_id, e.first_name, e.last_name,
       (SELECT COUNT(*) FROM customer c WHERE c.support_rep_id = e.employee_id) AS customer_count
FROM employee e
WHERE (SELECT COUNT(*) FROM customer c WHERE c.support_rep_id = e.employee_id) >
      (SELECT COUNT(*)::numeric / NULLIF(COUNT(DISTINCT support_rep_id), 0) FROM customer);
-- Verified result: Jane Peacock (21 customers) and Margaret Park (20) are above average.

-- 3.6  Window function: RANK() PARTITION BY
-- Top 3 most-purchased tracks within each genre.
-- NOTE: PostgreSQL has no QUALIFY clause (Snowflake/BigQuery only), so the
-- windowed result is wrapped in an outer SELECT and filtered there instead.
SELECT genre, track_name, times_purchased, genre_rank
FROM (
    SELECT g.name AS genre, t.name AS track_name,
           COUNT(il.invoice_line_id) AS times_purchased,
           RANK() OVER (PARTITION BY g.name ORDER BY COUNT(il.invoice_line_id) DESC) AS genre_rank
    FROM invoice_line il
    JOIN track t ON il.track_id = t.track_id
    JOIN genre g ON t.genre_id = g.genre_id
    GROUP BY g.name, t.name
) ranked
WHERE genre_rank <= 3
ORDER BY genre, genre_rank;

\c sales_db

-- 3.7  LEFT JOIN
-- Products in the catalog that were never ordered.
SELECT p.product_code, p.product_line
FROM products p
LEFT JOIN order_items oi ON p.product_code = oi.product_code
WHERE oi.product_code IS NULL;
-- Verified result: 0 rows -- every one of the 109 products sold at least once.

-- 3.8  INNER JOIN across three tables
-- Top 5 customers by revenue, with their territory.
SELECT c.customer_name, c.territory, SUM(oi.sales) AS total_revenue
FROM customers c
JOIN orders o      ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_number = oi.order_number
GROUP BY c.customer_name, c.territory
ORDER BY total_revenue DESC
LIMIT 5;
-- Verified result: Euro Shopping Channel (EMEA) leads at $912,294.11.

-- 3.9  Subquery
-- Customers whose total spend exceeds the average customer spend.
SELECT customer_name, total_spent
FROM (
    SELECT c.customer_name, SUM(oi.sales) AS total_spent
    FROM customers c
    JOIN orders o      ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_number = oi.order_number
    GROUP BY c.customer_name
) cust_spend
WHERE total_spent > (
    SELECT AVG(spend) FROM (
        SELECT SUM(oi.sales) AS spend
        FROM orders o
        JOIN order_items oi ON o.order_number = oi.order_number
        GROUP BY o.customer_id
    ) avg_sub
)
ORDER BY total_spent DESC
LIMIT 10;

-- 3.10  Window function: SUM() OVER (running / cumulative total)
-- Running cumulative monthly revenue for 2004.
SELECT month_id, monthly_sales,
       SUM(monthly_sales) OVER (ORDER BY month_id) AS running_total
FROM (
    SELECT o.month_id, SUM(oi.sales) AS monthly_sales
    FROM orders o
    JOIN order_items oi ON o.order_number = oi.order_number
    WHERE o.year_id = 2004
    GROUP BY o.month_id
) monthly
ORDER BY month_id;
-- Verified result: 2004 ends the year at a $4,724,162.60 cumulative total.

-- 3.11  Window function: ROW_NUMBER() PARTITION BY
-- Each customer's single largest order, ranked overall.
SELECT customer_name, order_number, order_total, rn
FROM (
    SELECT c.customer_name, o.order_number,
           SUM(oi.sales) AS order_total,
           ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY SUM(oi.sales) DESC) AS rn
    FROM customers c
    JOIN orders o      ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_number = oi.order_number
    GROUP BY c.customer_name, c.customer_id, o.order_number
) ranked
WHERE rn = 1
ORDER BY order_total DESC
LIMIT 5;
-- Verified result: Dragon Souveniers, Ltd.'s biggest single order was $77,809.37.


-- =====================================================================================
-- SECTION 4: BUSINESS PROBLEM SOLVING
-- =====================================================================================

\c chinook

-- 4.1  Top-performing products: best-selling artist by revenue
SELECT ar.name AS artist, SUM(il.unit_price * il.quantity) AS revenue,
       COUNT(DISTINCT il.invoice_id) AS invoices_appeared_in
FROM invoice_line il
JOIN track t   ON il.track_id = t.track_id
JOIN album al  ON t.album_id = al.album_id
JOIN artist ar ON al.artist_id = ar.artist_id
GROUP BY ar.name
ORDER BY revenue DESC
LIMIT 5;
-- Verified result: Iron Maiden leads at $138.60 across 30 invoices.

\c sales_db

-- 4.2  Revenue trend over time: month-over-month growth
SELECT year_id, month_id, monthly_sales,
       LAG(monthly_sales) OVER (ORDER BY year_id, month_id) AS prev_month_sales,
       ROUND(
         100.0 * (monthly_sales - LAG(monthly_sales) OVER (ORDER BY year_id, month_id))
         / NULLIF(LAG(monthly_sales) OVER (ORDER BY year_id, month_id), 0), 2
       ) AS mom_growth_pct
FROM (
    SELECT year_id, month_id, SUM(oi.sales) AS monthly_sales
    FROM orders o
    JOIN order_items oi ON o.order_number = oi.order_number
    GROUP BY year_id, month_id
) monthly
ORDER BY year_id, month_id;
-- Verified result: October 2003 spiked +115.28% month-over-month.

-- 4.3  Customer purchasing behavior: one-time vs. repeat customers
SELECT
    CASE WHEN order_count = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
    COUNT(*) AS num_customers,
    ROUND(AVG(total_spent), 2) AS avg_lifetime_value
FROM (
    SELECT c.customer_id, COUNT(DISTINCT o.order_number) AS order_count, SUM(oi.sales) AS total_spent
    FROM customers c
    JOIN orders o      ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_number = oi.order_number
    GROUP BY c.customer_id
) cust
GROUP BY customer_type;
-- Verified result: 91 of 92 customers (99%) are repeat buyers, averaging
-- $109,864.12 in lifetime spend vs. $34,993.92 for the single one-time buyer.


-- =====================================================================================
-- SECTION 5: QUERY OPTIMIZATION
-- =====================================================================================
-- All EXPLAIN ANALYZE output below is from real runs against the loaded data,
-- not estimated -- see the companion report for full plan output and discussion.

\c chinook

-- 5.1  A naturally-occurring index win: filtering by invoice_date
-- Before: invoice.invoice_date has no index -> PostgreSQL performs a Seq Scan.
EXPLAIN ANALYZE
SELECT customer_id, SUM(total)
FROM invoice
WHERE invoice_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY customer_id
ORDER BY SUM(total) DESC
LIMIT 5;
-- Verified: Seq Scan on invoice, cost 0.00..12.18, filters out 412 rows to find matches.

-- Add an index on the filtered column:
CREATE INDEX idx_invoice_date ON invoice(invoice_date);

-- After: the planner switches to an index-based plan on its own -- no query
-- rewrite needed. Depending on table statistics you may see "Index Scan
-- using idx_invoice_date" or "Bitmap Heap Scan" + "Bitmap Index Scan using
-- idx_invoice_date" (Postgres picks whichever is cheaper) -- both avoid the
-- full Seq Scan and both are correct outcomes here.
EXPLAIN ANALYZE
SELECT customer_id, SUM(total)
FROM invoice
WHERE invoice_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY customer_id
ORDER BY SUM(total) DESC
LIMIT 5;
-- Verified: plan cost drops from 12.14-12.19 (Seq Scan) to 8.32-8.92
-- (index-based scan) after the index is added.

\c sales_db

-- 5.2  Missing foreign-key indexes
-- PostgreSQL does NOT automatically index foreign-key columns (only the
-- referenced primary key gets an automatic unique index). orders.customer_id
-- and order_items.product_code were unindexed after the schema in Section 1.
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_items_product_code ON order_items(product_code);
-- Verified: on this data volume (307 orders / 2,823 order lines) PostgreSQL's
-- cost-based planner still prefers a Seq Scan for a single-customer lookup,
-- because scanning ~300 rows sequentially is cheaper than a random-access
-- index lookup at this scale -- this is correct, expected behavior, not a
-- missed optimization. Forcing SET enable_seqscan = off proves the index
-- is valid and would be chosen automatically once the table grows large
-- enough (typically tens of thousands of rows) for random I/O to be the
-- cheaper option. In a production-scale sales system (millions of order
-- rows), these two indexes are essential and the planner will use them
-- without being forced.

-- 5.3  Clean, readable SQL and optimization habits applied throughout this file:
--   - Never SELECT * in a final deliverable query; only needed columns are selected.
--   - Aggregate first in a subquery, then join/filter the pre-aggregated result,
--     to avoid re-computing SUM()/COUNT() once per join fan-out row.
--   - Consistent lower_snake_case naming and explicit JOIN ... ON syntax
--     (never implicit comma joins) for readability and predictable plans.
--   - Filtering (WHERE) is pushed as early as possible so the planner can use
--     an index or discard rows before the (more expensive) join/aggregate steps.
--   - Every foreign key used in a JOIN or WHERE clause across both databases
--     now has a supporting index (Chinook ships with these; sales_db needed
--     them added manually, per 5.2).

