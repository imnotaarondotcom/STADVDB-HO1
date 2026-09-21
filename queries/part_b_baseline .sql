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
JOIN rental AS r
    ON r.customer_id = c.customer_id
JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = c.customer_id
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
JOIN rental AS r
    ON r.customer_id = c.customer_id
JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spent DESC
LIMIT 10;

-- Record after execution:
-- Execution time: 94.44 ms
-- Potential Bottleneck: Payment JOIN contributes much to the total costs, approximately 5558 of the total cost 7545.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: customer = all are scanned, rental = index lookup using customer_id, payment = index lookup using both customer_id and rental_id
-- Indexes used: No new indices used. rental and payment indices used.
-- Estimated rows processed: 407 GROUPED rows
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 7545.

-- =========================================================
-- QUERY 2: Payments above each customer's own average payment
-- Analytical question: Which individual rental payments were unusually high compared with that customer's normal spending?
-- Uses: customer + rental + payment
-- Includes the required correlated subquery.
-- =========================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.store_id,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_spent,
    ROUND(AVG(p.amount), 2) AS average_payment
FROM customer AS c
JOIN rental AS r
    ON r.customer_id = c.customer_id
JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = c.customer_id
WHERE c.active = 1
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name,
    c.store_id
HAVING COUNT(DISTINCT r.rental_id) >= 10
ORDER BY
    total_spent DESC,
    total_rentals DESC
LIMIT 20;

EXPLAIN
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.store_id,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    COUNT(p.payment_id) AS total_payments,
    ROUND(SUM(p.amount), 2) AS total_spent,
    ROUND(AVG(p.amount), 2) AS average_payment
FROM customer AS c
JOIN rental AS r
    ON r.customer_id = c.customer_id
JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = c.customer_id
WHERE c.active = 1
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name,
    c.store_id
HAVING COUNT(DISTINCT r.rental_id) >= 10
ORDER BY
    total_spent DESC,
    total_rentals DESC
LIMIT 20;

-- Record after execution:
-- Execution time: 98.431 ms
-- Potential Bottleneck: Inner Loop JOIN for payments costs too much.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: customer = all are scanned, filtered by active = 1, rental & payment = index lookup
-- Indexes used: No new indices used. rental and payment indices used.
-- Estimated rows processed: 407 GROUPED rows
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 3833.

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
JOIN customer AS c
    ON c.customer_id = r.customer_id
LEFT JOIN payment AS p
    ON p.rental_id = r.rental_id
   AND p.customer_id = r.customer_id
GROUP BY
    c.store_id,
    DATE_FORMAT(r.rental_date, '%Y-%m')
ORDER BY
    c.store_id ASC,
    rental_month ASC;

EXPLAIN
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
    DATE_FORMAT(r.rental_date, '%Y-%m')
ORDER BY
    c.store_id ASC,
    rental_month ASC;

-- Record after execution:
-- Execution time: 142.265 ms
-- Potential Bottleneck: LEFT JOIN preserves rentals even when no matching payments exist.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: customers = Index scan; scans store_id's, rental = Index lookup; finds rentals for each customer, payment = Index lookup
-- Indexes used: No new indices created. Indices for rental and payment used. Index for store_id used in customer.
-- Estimated rows processed: 15881
-- Estimated cost of query and other relevant execution-plan: Nested inner and left joins leads to 11178 cost.

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
-- Execution time: 110.556 ms
-- Potential Bottleneck: The LEFT JOIN cost for rental and customer is too high.

-- MAIN EXPLAIN OBSERVATIONS
-- Type of Access for each table: customers = all, rental and payment = index lookup
-- Indexes used: No new indices created. Indices for customer and rental used.
-- Estimated rows processed: 599
-- Estimated cost of query and other relevant execution-plan: Nested Loops and Aggregations raise estimated costs to 11021