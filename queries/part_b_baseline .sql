USE sakila;

/*
PART B - BASELINE ANALYTICAL QUERIES
Tables used only: customer, rental, payment

For each query:
1. Run the SELECT and record the Execution time shown by MySQL Workbench.
2. Run the EXPLAIN version to show costs per action and table rows explored/processed.
3. Run EXPLAIN FORMAT=JSON if you need the optimizer's estimated cost (cost_info/query_cost).

*/

-- =========================================================
-- QUERY 1: Top 10 customers by total spending
-- Analytical question: Which customers generated the most revenue, and how many rentals/payments did they make?
-- Uses: customer + rental + payment
-- =========================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_spent
FROM customer AS c
JOIN rental AS r ON r.customer_id = c.customer_id
JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spent DESC
LIMIT 10;

EXPLAIN
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_spent
FROM customer AS c
JOIN rental AS r ON r.customer_id = c.customer_id
JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spent DESC
LIMIT 10;

-- Record after execution:
-- Execution time: 773.43ms
-- Potential Bottleneck: Payment JOIN contributes much to the total costs, approximately 42365 of the total cost 55375.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: MySQL scans the rental index first, performs indexed lookups on payment, and uses a single-row primary-key lookup on customer.
-- Indexes used: The query uses idx_fk_customer_id for rental, fk_payment_rental for payment, and the PRIMARY index for customer.
-- Estimated rows processed: Scans about 119775 rental index entries and estimates 5989 GROUPED rows after the joins.
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 56826.

-- =========================================================
-- QUERY 2: Top 20 customers with highest average payment
-- Analytical question: Among customers with at least 30 transactions, which customers have the highest average payment amount?
-- Uses: customer + rental + payment
-- Includes the required correlated subquery.
-- =========================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(p.payment_id) AS total_payments,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    ROUND(AVG(p.amount), 2) AS average_payment,
    ROUND(SUM(p.amount), 2) AS total_spent
FROM customer AS c
JOIN rental AS r ON r.customer_id = c.customer_id
JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = c.customer_id
WHERE c.active = 1
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(p.payment_id) >= 30
ORDER BY average_payment DESC
LIMIT 20;

EXPLAIN
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(p.payment_id) AS total_payments,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    ROUND(AVG(p.amount), 2) AS average_payment,
    ROUND(SUM(p.amount), 2) AS total_spent
FROM customer AS c
JOIN rental AS r ON r.customer_id = c.customer_id
JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = c.customer_id
WHERE c.active = 1
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(p.payment_id) >= 30
ORDER BY average_payment DESC
LIMIT 20;

-- Record after execution:
-- Execution time: 776.866ms
-- Potential Bottleneck: Inner Loop JOIN for payments costs too much.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: MySQL scans and filters the customer table for active customers while using indexed lookups for the rental and payment tables.
-- Indexes used: Existing indexes on the rental and payment tables are used, while no additional specialized index is used for the active customer filter.
-- Estimated rows processed: 2355 GROUPED rows
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 27773.

-- =========================================================
-- QUERY 3: Monthly Rental and Revenue Trend by Store
-- Analytical question: How have rental volume and revenue of each store changed per month by store?
-- Uses: rental + customer + payment
-- =========================================================

SELECT
    c.store_id,
    DATE_FORMAT(r.rental_date, '%Y-%m') AS rental_month,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(AVG(p.amount), 2) AS average_payment
FROM rental AS r
JOIN customer AS c ON c.customer_id = r.customer_id
LEFT JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = r.customer_id
GROUP BY c.store_id, DATE_FORMAT(r.rental_date, '%Y-%m')
ORDER BY c.store_id ASC, rental_month ASC;

EXPLAIN
SELECT
    c.store_id,
    DATE_FORMAT(r.rental_date, '%Y-%m') AS rental_month,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(AVG(p.amount), 2) AS average_payment
FROM rental AS r
JOIN customer AS c ON c.customer_id = r.customer_id
LEFT JOIN payment AS p ON p.rental_id = r.rental_id AND p.customer_id = r.customer_id
GROUP BY c.store_id, DATE_FORMAT(r.rental_date, '%Y-%m')
ORDER BY c.store_id ASC, rental_month ASC;

-- Record after execution:
-- Execution time: 1.2913844585418701s
-- Potential Bottleneck: LEFT JOIN preserves rentals even when no matching payments exist.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: MySQL performs an index scan on customer and indexed lookups on rental and payment, with payment accessed through a LEFT JOIN.
-- Indexes used: No new indices created. Existing indexes for customer.store_id, rental, and payment are used, with no new indexes introduced for the query.
-- Estimated rows processed: 121852 rows
-- Estimated cost of query and other relevant execution-plan: Nested inner and left joins leads to 81588 cost.

-- =========================================================
-- QUERY 4: Difference in rental activity and revenue between active and inactive customers
-- Analytical question: How does rental activity and revenue differ between active and inactive customers?
-- Uses: customer + rental + payment
-- =========================================================

SELECT 
    c.active,
    COUNT(DISTINCT c.customer_id) AS customers,
    COUNT(DISTINCT r.rental_id) AS rentals,
    COALESCE(SUM(p.amount), 0) AS revenue
FROM customer c
LEFT JOIN rental r ON r.customer_id = c.customer_id
LEFT JOIN payment p ON p.rental_id = r.rental_id
GROUP BY c.active
ORDER BY revenue DESC;

EXPLAIN
SELECT 
    c.active,
    COUNT(DISTINCT c.customer_id) AS customers,
    COUNT(DISTINCT r.rental_id) AS rentals,
    COALESCE(SUM(p.amount), 0) AS revenue
FROM customer c
LEFT JOIN rental r ON r.customer_id = c.customer_id
LEFT JOIN payment p ON p.rental_id = r.rental_id
GROUP BY c.active
ORDER BY revenue DESC;

-- Record after execution:
-- Execution time: 831.292ms
-- Potential Bottleneck: The LEFT JOIN cost for rental and customer is too high.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: MySQL performs a full scan of customer and uses indexed lookups on rental and payment through the two LEFT JOIN operations.
-- Indexes used: Existing indexes on the customer relationships in rental and the rental relationship in payment are used, although the customer table itself is scanned.
-- Estimated rows processed: 38.7 rows
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 81890.
