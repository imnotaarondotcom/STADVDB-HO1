-- Database Schema Modification Script
-- Description: Upgrades rental_id and payment_id to BIGINT to handle >100k synthetic rows.

USE sakila;

-- Temporarily drop FK constraint to modify column types
ALTER TABLE payment DROP FOREIGN KEY fk_payment_rental;

-- Upgrade primary and foreign key columns to BIGINT AUTO_INCREMENT
ALTER TABLE rental MODIFY rental_id BIGINT AUTO_INCREMENT;
ALTER TABLE payment MODIFY payment_id BIGINT AUTO_INCREMENT;
ALTER TABLE payment MODIFY rental_id BIGINT;

-- Re-add foreign key constraint with cascade options
ALTER TABLE payment 
  ADD CONSTRAINT fk_payment_rental 
  FOREIGN KEY (rental_id) REFERENCES rental (rental_id) 
  ON DELETE SET NULL ON UPDATE CASCADE;