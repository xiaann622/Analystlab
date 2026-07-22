# SQL Analytics Project: Chinook Database & Sample Sales Data
### PostgreSQL 16 — Setup, Core & Advanced Queries, Business Insights, Optimization

This report documents a complete SQL analytics project built on two public datasets. Every query referenced below was executed against a live PostgreSQL 16 instance with the real data loaded — the numbers quoted are actual results, not estimates. The companion file `sql_analysis_project.sql` contains the runnable script; section numbers here match that file exactly.

**Data sources**
- Chinook Database (digital music store schema and sample data) — https://github.com/lerocha/chinook-database, maintained by Luis Rocha, MIT licensed.
- Sample Sales Data (fictional wholesale toy/collectibles distributor) — https://www.kaggle.com/datasets/kyanyoga/sample-sales-data, by kyanyoga on Kaggle.

---

## 1. Database Setup

### 1.1 Chinook
Chinook is distributed as a ready-made PostgreSQL script that creates its own database and loads everything in one pass. After running it, the schema looks like this:

```
artist ─┬─< album ─┬─< track ─┬─< invoice_line >─┬─ invoice ─>─ customer ─>─ employee (support_rep)
        │          │          ├─> genre           │
        │          │          └─> media_type      │
        └──────────┘                              └── employee (reports_to, self-referencing)
playlist ─< playlist_track >─ track
```

Every foreign key in Chinook ships with a supporting index already (verified via `pg_indexes`), which matters later in the optimization section. Verified row counts after load: `album` 347, `artist` 275, `customer` 59, `employee` 8, `genre` 25, `invoice` 412, `invoice_line` 2,240, `media_type` 5, `playlist` 18, `playlist_track` 8,715, `track` 3,503.

### 1.2 Sample Sales Data
The Kaggle file is a single flat CSV — 25 columns, 2,823 rows — where every row mixes order-header, order-line, customer, and product fields together (e.g. `ORDERNUMBER`, `SALES`, `CUSTOMERNAME`, `PRODUCTCODE` all in one record). Two design choices were worth flagging:

- **Encoding**: the file ships in Latin-1, not UTF-8 (it contains accented names like *Stadtish Fahrradgesellschaft*). Loading it directly into a UTF-8 database throws an encoding error, so it must be re-encoded first with `iconv -f latin1 -t utf-8` before `\copy`.
- **Normalization**: rather than querying one wide table for the whole project, the raw CSV is loaded into a staging table (`sales_raw`) and then split into a proper star schema — `customers`, `products`, `orders`, `order_items` — with real primary keys, foreign keys, and `CHECK` constraints. This is what lets Section 3 demonstrate genuine multi-table joins instead of just filtering one table.

Verified population: 92 distinct customers, 109 distinct products, 307 orders, and 2,823 order line items — the line-item count matches `sales_raw` exactly, confirming no rows were lost during normalization.

---

## 2. Core SQL Queries

**2.1 — SELECT / WHERE / ORDER BY (Chinook).** Rock tracks over 5 minutes, longest first. Top result: *"Dazed And Confused"* by Led Zeppelin at ~27 minutes (1,612 seconds) — a live recording, which explains the outlier length.

**2.2 — GROUP BY / HAVING (Chinook).** Genres with more than 100 tracks and their average length. Rock dominates the catalog with 1,297 tracks (37% of the entire library), averaging 4.73 minutes per track.

**2.3 — Aggregates: SUM, COUNT (Chinook).** Revenue and invoice count by billing country. The USA leads with 91 invoices and $523.06 in revenue, followed by Canada ($303.96) and France ($195.10) — a long tail typical of a digital storefront with a home-market bias.

**2.4 — SELECT / WHERE / ORDER BY (Sales).** All "Large" deals placed in 2004: 6 orders, spread from February through November — large deals are rare events, not a steady monthly occurrence.

**2.5 — GROUP BY / HAVING (Sales).** Product lines generating over $500K in total sales. **Classic Cars dominates at $3.92M across 199 orders** — more than double the next category (Vintage Cars, $1.90M). This single finding should drive inventory and marketing priority.

---

## 3. Advanced SQL Concepts

**3.1 — INNER JOIN, 3 tables (Chinook).** Top 5 tracks by revenue (`track → album → artist`). Iron Maiden's *"The Trooper"* leads at $4.95 — a reminder that in a $0.99-per-track catalog, "top seller" differences are won on volume of individual purchases, not price.

**3.2 — LEFT JOIN (Chinook).** Tracks that have never appeared on an invoice. **1,519 of 3,503 tracks (43%) have never sold a single copy.** This is a real, verified finding worth calling out: nearly half the catalog is effectively dead inventory — a strong candidate for a "long tail" analysis or a delisting/promotion decision.

**3.3 — RIGHT JOIN (Chinook).** Every genre with its track count, including thinly stocked genres. "Opera" has exactly 1 track — RIGHT JOIN guarantees it still shows up even though it barely participates in the join, which is the whole point of choosing RIGHT over INNER here.

**3.4 — Subquery in WHERE (Chinook).** Customers spending above the average customer's total. Helena Holý tops the list at $49.62 lifetime spend — useful for a "who are our above-average customers" retention query.

**3.5 — Correlated subquery (Chinook).** Support reps handling more customers than the company average. Two of three reps clear the bar: Jane Peacock (21 customers) and Margaret Park (20) — the third rep is carrying a below-average book, worth investigating for staffing or performance reasons.

**3.6 — Window function, RANK() PARTITION BY (Chinook).** Top 3 most-purchased tracks per genre, in one pass, without a self-join or per-genre subquery. This is the kind of "top-N per group" question that used to require correlated subqueries or `UNION ALL` per category before window functions existed.

**3.7 — LEFT JOIN (Sales).** Products in the catalog never ordered: **0 rows.** Every one of the 109 products sold at least once — unlike the Chinook catalog, this product line has no dead SKUs, a meaningfully different inventory picture between the two datasets.

**3.8 — INNER JOIN, 3 tables (Sales).** Top 5 customers by revenue with territory. Euro Shopping Channel (EMEA) leads at $912,294.11 — nearly 40% more than the #2 customer (Mini Gifts Distributors, NA, $654,858.06).

**3.9 — Subquery (Sales).** Customers above the average customer spend — 10 customers qualify, the same top names as 3.8, confirming the revenue concentration is real and not a join artifact.

**3.10 — Window function, SUM() OVER (Sales).** Running cumulative revenue for 2004. The year closes at **$4,724,162.60 cumulative**, with a visible spike in November alone ($1,089,048 — 23% of the whole year in one month), consistent with year-end/holiday ordering patterns.

**3.11 — Window function, ROW_NUMBER() PARTITION BY (Sales).** Each customer's single largest order, ranked. Dragon Souveniers, Ltd. placed the single biggest order in the dataset: $77,809.37 in one transaction.

---

## 4. Business Problem Solving

**4.1 — Top-performing products/artists (Chinook).** Iron Maiden is the top artist by revenue ($138.60 across 30 invoices), narrowly ahead of U2 ($105.93, but across more invoices — 32). Note the distinction: Iron Maiden earns more per invoice appearance, U2 appears in more invoices. Depending on the business question ("who earns us the most" vs. "who is most broadly popular"), the answer differs — worth stating explicitly rather than picking one metric silently.

**4.2 — Revenue trend over time (Sales).** Month-over-month growth, computed with `LAG()`. The standout month is **October 2003, up 115.28%** month-over-month, followed by a further 81.22% jump in November 2003 before a sharp -74.57% pullback in December. This look like a strong Q4 seasonal ordering pattern (retailers stocking up ahead of the holidays) followed by the expected post-season drop — the kind of insight a plain revenue-by-month bar chart hides but `LAG()` surfaces directly.

**4.3 — Customer purchasing behavior (Sales).** One-time vs. repeat customers. **91 of 92 customers (99%) are repeat buyers**, averaging $109,864 in lifetime spend — over 3x the $34,994 the single one-time buyer generated. This is a strong signal that the business is retention-driven, not acquisition-driven: nearly the entire customer base returns, and repeat customers are dramatically more valuable per capita.

---

## 5. Query Optimization

**5.1 — A naturally occurring index win (Chinook).** Filtering `invoice` by `invoice_date` had no supporting index initially, so PostgreSQL used a `Seq Scan` (cost ≈ 12.1–12.2). After `CREATE INDEX idx_invoice_date ON invoice(invoice_date);`, the planner switched — without any query rewrite — to an index-based plan (`Index Scan` or `Bitmap Heap Scan` over `Bitmap Index Scan`, depending on current table statistics), dropping the cost to ≈ 8.3–8.9. This is the textbook case for the concept: index the columns your `WHERE` clauses actually filter on.

**5.2 — Missing foreign-key indexes (Sales).** This is worth explaining carefully, because the honest result contradicts the "just add an index" intuition many optimization guides teach:

PostgreSQL does **not** automatically index foreign-key columns — only the referenced primary key gets an automatic unique index. After the Section 1 schema, `orders.customer_id` and `order_items.product_code` had no index at all. Two indexes were added:

```sql
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_items_product_code ON order_items(product_code);
```

But when the resulting query plan was checked with `EXPLAIN ANALYZE`, PostgreSQL **still chose a sequential scan** over the new index for a single-customer lookup. This is correct, expected behavior, not a failed optimization: `orders` only has 307 rows, so scanning all of them sequentially (one cheap, predictable disk read) is actually less work than a random-access index lookup at this scale. Forcing the index with `SET enable_seqscan = off` confirmed the index itself is valid and would be picked automatically once the table grows large enough — typically tens of thousands of rows — for random I/O to become the cheaper option. **The lesson documented here is that indexing decisions are cost-based and data-volume-dependent, not a blanket rule** — these two indexes are essential scaffolding for when this sales system operates at production scale (millions of order rows), even though they don't change today's query plan on a 307-row table.

**5.3 — Clean, readable SQL practices applied throughout.**
- No `SELECT *` in any final deliverable query — only the columns actually needed.
- Aggregation is done in a subquery first, then joined/filtered on the pre-aggregated result, to avoid recomputing `SUM()`/`COUNT()` once per join fan-out row (see 3.9, 3.11).
- Explicit `JOIN ... ON` syntax throughout — no implicit comma joins — for both readability and predictable query plans.
- `WHERE` filters are pushed as early as possible so the planner can use an index or discard rows before the more expensive join/aggregate steps.
- Every foreign key used in a `JOIN` or `WHERE` clause across both databases now has a supporting index (Chinook ships with these; `sales_db` needed them added manually, as documented in 5.2).

---

## 6. Summary of Key Insights

| # | Finding | Source |
|---|---|---|
| 1 | Classic Cars is the dominant product line: $3.92M / 199 orders, 2x the next category | Sales, Q2.5 |
| 2 | 43% of the Chinook music catalog (1,519 of 3,503 tracks) has never sold a single copy | Chinook, Q3.2 |
| 3 | 99% of sales customers are repeat buyers, worth 3x a one-time buyer on average | Sales, Q4.3 |
| 4 | Q4 2003 shows a sharp seasonal spike (Oct +115%, Nov +81%) then a post-holiday pullback | Sales, Q4.2 |
| 5 | Revenue concentration is real: the top customer (Euro Shopping Channel) generates 40% more than the #2 customer | Sales, Q3.8/3.9 |
| 6 | Indexing decisions depend on data volume — the same index can be correct architecture yet unused by the planner today | Both, Section 5 |

## Tools Used
PostgreSQL 16 (server + `psql` client). Any GUI client such as pgAdmin or DBeaver can connect to the same database and run `sql_analysis_project.sql` directly — no query in the script depends on the command-line client beyond the `\c` (connect) and `\copy` (bulk load) meta-commands, which pgAdmin/DBeaver both support natively.

## Limitations
Both datasets are intentionally small (a few hundred to a few thousand rows), which is ideal for learning SQL syntax but means some optimization comparisons (Section 5.2) show the *concept* correctly without showing dramatic speed differences that only appear at production scale — this is called out explicitly rather than glossed over.
