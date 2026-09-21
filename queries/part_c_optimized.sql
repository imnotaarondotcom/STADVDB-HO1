USE sakila;

-- =========================================================
-- OPTIMIZED QUERY 1: Top 10 customers by total spending
-- Technique: Indexing and Reformulating Subqueries
-- =========================================================

CREATE INDEX idx_customer_payment_amount
	ON payment (customer_id, amount);
    
SELECT
	c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    r.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

EXPLAIN
SELECT
	c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    r.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent
FROM customer AS c
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
ORDER BY total_spent DESC
LIMIT 10;

-- =========================================================
-- OPTIMIZED QUERY 2: Payments above each customer's own average payment
-- Technique: Reformulating Subqueries
-- =========================================================

SELECT
	c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.store_id,
    r.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent,
    ROUND(p.total_spent / p.total_payments, 2) AS average_payment
FROM customer as c
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
    HAVING COUNT(*) >= 10
) AS r ON r.customer_id = c.customer_id
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
WHERE c.active = 1
ORDER BY
	total_spent DESC,
    total_rentals DESC
LIMIT 20;

EXPLAIN ANALYZE
SELECT
	c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.store_id,
    r.total_rentals,
    p.total_payments,
    ROUND(p.total_spent, 2) AS total_spent,
    ROUND(p.total_spent / p.total_payments, 2) AS average_payment
FROM customer as c
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
    HAVING COUNT(*) >= 10
) AS r ON r.customer_id = c.customer_id
JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_payments,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
WHERE c.active = 1
ORDER BY
	total_spent DESC,
    total_rentals DESC
LIMIT 20;

-- =========================================================
-- OPTIMIZED QUERY 3: Monthly Rental and Revenue Trend by Store
-- Technique: Denormalization
-- =========================================================

CREATE TABLE store_month_revenue AS
SELECT
	c.store_id,
    r.rental_month,
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
    r.rental_month;

ALTER TABLE store_month_revenue
	ADD PRIMARY KEY (store_id, rental_month);

SELECT *
FROM store_month_revenue
ORDER BY
	store_id ASC,
    rental_month ASC;

EXPLAIN
SELECT *
FROM store_month_revenue
ORDER BY
	store_id ASC,
    rental_month ASC;
    
-- =========================================================
-- QUERY 4: Difference in rental activity and revenue between active and inactive customers
-- Technique: Reformulating Subqueries
-- =========================================================

SELECT
	c.active,
    COUNT(*) AS customers,
    COALESCE(SUM(r.total_rentals), 0) AS rentals,
    COALESCE(SUM(p.total_spent), 0) AS revenue
FROM customer AS c
LEFT JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
LEFT JOIN (
	SELECT
		customer_id,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
GROUP BY c.active
ORDER BY revenue DESC;

EXPLAIN ANALYZE
SELECT
	c.active,
    COUNT(*) AS customers,
    COALESCE(SUM(r.total_rentals), 0) AS rentals,
    COALESCE(SUM(p.total_spent), 0) AS revenue
FROM customer AS c
LEFT JOIN (
	SELECT
		customer_id,
        COUNT(*) AS total_rentals
	FROM rental
    GROUP BY customer_id
) AS r ON r.customer_id = c.customer_id
LEFT JOIN (
	SELECT
		customer_id,
        SUM(amount) AS total_spent
	FROM payment
    GROUP BY customer_id
) AS p ON p.customer_id = c.customer_id
GROUP BY c.active
ORDER BY revenue DESC;
