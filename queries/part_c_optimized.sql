USE sakila;

/*
PART C - OPTIMIZED ANALYTICAL QUERIES
Tables used only: customer, rental, payment

Optimization techniques used:
  - Indexes
  - Denormalization
  - Reformulating Subqueries

For each query:
1. Run the SELECT and record the Execution time shown by MySQL Workbench.
2. Run the EXPLAIN version to show costs per action and table rows explored/processed.
3. Swap in EXPLAIN FORMAT=JSON / EXPLAIN ANALYZE as needed for the cost and real row counts.
 
NOTE: run the SETUP block once first before timing anything. The DROPs make this
script safely re-runnable. Not running these first causes the CREATE statements fail on a
second execution.
*/

-- =========================================================
-- SETUP: indexes and cleanup (run once, before timing)
-- =========================================================

DROP INDEX idx_payment_customer_rental_amount ON payment;
DROP TABLE IF EXISTS store_month_revenue;

-- Covering index for Q1, Q2 and Q4.
-- All three only ever read customer_id, rental_id and amount from payment.
-- Every one of them can now be answered from the index alone without touching the table rows.
CREATE INDEX idx_payment_customer_rental_amount
	ON payment (customer_id, rental_id, amount);

-- =========================================================
-- OPTIMIZED QUERY 1: Top 10 customers by total spending
-- Technique: Indexing + Reformulating Subqueries
-- =========================================================

SELECT
	c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    p.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
    SELECT
        customer_id,
        COUNT(DISTINCT rental_id) AS total_rentals,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

EXPLAIN
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    p.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
    SELECT
        customer_id,
        COUNT(DISTINCT rental_id) AS total_rentals,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

-- Record after execution:
-- Baseline execution time: 773.43 ms  (baseline cost 55375)
-- Optimized execution time: 94 ms
-- Key change: Rental join removed entirely; three-table row-level join replaced by a single
-- covering-index scan on payment feeding a derived table, joined to customer on 10 rows only
 
-- MAIN EXPLAIN OBSERVATIONS
-- Type of access for each table: payment (inside derived table) = index (Using index, covering);
-- customer = eq_ref on PRIMARY (1 row per lookup, matched to the derived table's customer_id);
-- derived table = materializes once (rows=1500), then table-scanned for the sort
-- Indexes used: idx_payment_customer_rental_amount (customer_id, rental_id, amount) on payment;
-- PRIMARY on customer
-- Estimated rows processed: 120,000 index entries scanned -> 1,500 grouped rows materialized ->
-- 10 rows after LIMIT (EXPLAIN ANALYZE actual: derived table materializes to 1,500 rows,
-- final join produces 10 rows in 97.3 ms instrumented time)
-- Estimated cost: 55,502.50 (payment subquery alone: 12,104.25)

-- =========================================================
-- OPTIMIZED QUERY 2: Top 20 customers with highest average payment
-- Technique: Reformulating Subqueries (reuses the Q1 index)
-- =========================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    p.total_payments,
    p.total_rentals,
    ROUND(p.average_payment, 2) AS average_payment,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
    SELECT
        customer_id,
        COUNT(*) AS total_payments,
        COUNT(DISTINCT rental_id) AS total_rentals,
        AVG(amount) AS average_payment,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
    HAVING COUNT(*) >= 30
) AS p ON p.customer_id = c.customer_id
WHERE c.active = 1
ORDER BY average_payment DESC, c.customer_id ASC
LIMIT 20;

EXPLAIN
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    p.total_payments,
    p.total_rentals,
    ROUND(p.average_payment, 2) AS average_payment,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
    SELECT
        customer_id,
        COUNT(*) AS total_payments,
        COUNT(DISTINCT rental_id) AS total_rentals,
        AVG(amount) AS average_payment,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
    HAVING COUNT(*) >= 30
) AS p ON p.customer_id = c.customer_id
WHERE c.active = 1
ORDER BY average_payment DESC, c.customer_id ASC
LIMIT 20;

-- Record after execution:
-- Baseline execution time: 776.866 ms  (baseline cost 27773)
-- Optimized execution time: 94 ms
-- Key change: HAVING COUNT(*) >= 30 pushed into the derived table, cutting 1,500 grouped
-- customers to 1,243 before the join to customer; AVG computed inside the subquery so
-- rounding matches the baseline exactly.
 
-- MAIN EXPLAIN OBSERVATIONS
-- Type of access for each table: customer = ALL, filtered by active = 1 (filtered 10.00%,
-- meaning MySQL's own estimate expects only ~150 of 1,500 rows to match -- actual is 1,432,
-- a case where the optimizer's estimate is badly off); payment (inside derived table) = index
-- (Using index, covering); derived table = ref lookup on auto-generated key (customer_id)
-- Indexes used: idx_payment_customer_rental_amount on payment; no index on customer.active
-- (95% of customers are active, so it would not be selective)
-- Estimated rows processed: 120,000 payment rows scanned -> 1,500 grouped -> 1,243 pass
-- HAVING >= 30 -> 1,189 rows after the join to active customers (EXPLAIN ANALYZE actual:
-- Filter active=1 actual rows=1432; Materialize actual rows=1243; final join actual rows=1189
-- in 140 ms instrumented time)
-- Estimated cost: 4,352.50 (payment subquery alone: 12,104.25) -- lower than the baseline's
-- 27,773, unlike Q1/Q4, since the HAVING filter here shrinks the derived table the optimizer
-- sees, rather than being invisible to it

-- =========================================================
-- OPTIMIZED QUERY 3: Monthly Rental and Revenue Trend by Store
-- Technique: Denormalization (+ indexing via the primary key)
-- =========================================================

CREATE TABLE store_month_revenue AS
SELECT
    c.store_id,
    DATE_FORMAT(r.rental_date, '%Y-%m') AS rental_month,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(AVG(p.amount), 2) AS average_payment
FROM rental AS r
JOIN customer AS c
    ON c.customer_id = r.customer_id
LEFT JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = r.customer_id
GROUP BY
    c.store_id,
    DATE_FORMAT(r.rental_date, '%Y-%m');
 
ALTER TABLE store_month_revenue
    MODIFY rental_month CHAR(7) NOT NULL,
    ADD PRIMARY KEY (store_id, rental_month);

SELECT *
FROM store_month_revenue
ORDER BY store_id ASC, rental_month ASC;
 
EXPLAIN
SELECT *
FROM store_month_revenue
ORDER BY store_id ASC, rental_month ASC;
 
-- Record after execution:
-- Baseline execution time: 1291.38 ms  (baseline cost 81588, 121044 rows)
-- Optimized execution time: 15 ms
-- One-time cost to build store_month_revenue: record separately, not counted against the
-- 15 ms above -- this is a build-once cost, not part of the recurring report
-- Key change: 121,044-row join + aggregation replaced by a 12-row read of a precomputed
-- table. Primary key (store_id, rental_month) already matches the required ORDER BY, so
-- there is no filesort at all.
 
-- MAIN EXPLAIN OBSERVATIONS
-- Type of access: store_month_revenue = index scan on PRIMARY (clustered index, already in
-- sort order -- Extra column is empty, confirming no filesort, no temp table)
-- Indexes used: PRIMARY (store_id, rental_month)
-- Estimated rows processed: 12 (EXPLAIN ANALYZE actual: 12 rows in 0.0701 ms instrumented time)
-- Estimated cost: 1.45 -- by far the lowest of all four queries, and for once cost and real
-- execution time agree, because there is no derived table for the optimizer to misjudge

-- =========================================================
-- OPTIMIZED QUERY 4: Active vs inactive customers
-- Technique: Reformulating Subqueries (reuses the Q1 index)
-- =========================================================

SELECT
    c.active,
    COUNT(*) AS customers,
    COALESCE(SUM(r.total_rentals), 0) AS rentals,
    COALESCE(SUM(p.total_spent), 0) AS revenue
FROM customer AS c
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS total_rentals
    FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
LEFT JOIN (
    SELECT customer_id, SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
GROUP BY c.active
ORDER BY revenue DESC;

EXPLAIN
SELECT
    c.active,
    COUNT(*) AS customers,
    COALESCE(SUM(r.total_rentals), 0) AS rentals,
    COALESCE(SUM(p.total_spent), 0) AS revenue
FROM customer AS c
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS total_rentals
    FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
LEFT JOIN (
    SELECT customer_id, SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
GROUP BY c.active
ORDER BY revenue DESC;
 
-- Record after execution:
-- Baseline execution time: 831.292 ms  (baseline cost 81890)
-- Optimized execution time: 109 ms
-- Key change: Two chained LEFT JOINs that fanned out to one row per payment replaced by two
-- independent per-customer derived tables (rental, payment), each joined to customer once
-- instead of once per payment row; outer GROUP BY now works on 1,500 rows instead of ~120,000.
 
-- MAIN EXPLAIN OBSERVATIONS
-- Type of access for each table: rental (inside derived table) = index (Using index, covering,
-- via idx_fk_customer_id); payment (inside derived table) = index (Using index, covering, via
-- idx_payment_customer_rental_amount); customer = ALL (full scan, unavoidable -- every customer
-- is output whether or not they rented or paid)
-- Indexes used: idx_fk_customer_id on rental; idx_payment_customer_rental_amount on payment;
-- both derived-table joins use MySQL's own internal auto-generated key on customer_id
-- Estimated rows processed: rental derived table materializes 1,500 rows (from 119,801 scanned),
-- payment derived table materializes 1,500 rows (from 120,000 scanned), outer join produces
-- 1,500 rows collapsed to 2 by GROUP BY (EXPLAIN ANALYZE actual: both derived tables actually
-- materialize to 1,500 rows exactly, final output rows=2, in 115 ms instrumented time)
-- Estimated cost: 3,390,670.75 -- the largest gap between estimate and reality of all four
-- queries (estimated 3.06 billion intermediate rows from the nested LEFT JOINs vs. 1,500
-- actual)
