# GENERATED WITH GEMINI

import os
import random
from datetime import datetime, timedelta
import mysql.connector
from faker import Faker
import numpy as np

# Configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'user': os.getenv('DB_USER', 'root'),          # Change to your MySQL username
    'password': os.getenv('DB_PASSWORD', 'password'),  # Change to your MySQL password
    'database': os.getenv('DB_NAME', 'sakila'),
    'port': int(os.getenv('DB_PORT', 3306))
}

TARGET_CUSTOMERS = 1500
TARGET_RENTALS = 120000
TARGET_PAYMENTS = 120000
BATCH_SIZE = 5000

fake = Faker()

def get_db_connection():
    return mysql.connector.connect(**DB_CONFIG)

def fetch_existing_keys(cursor):
    """Fetch existing valid foreign keys from reference tables."""
    print("Fetching reference Foreign Keys from existing database...")
    
    cursor.execute("SELECT store_id FROM store")
    store_ids = [r[0] for r in cursor.fetchall()]

    cursor.execute("SELECT address_id FROM address")
    address_ids = [r[0] for r in cursor.fetchall()]

    cursor.execute("SELECT staff_id FROM staff")
    staff_ids = [r[0] for r in cursor.fetchall()]

    cursor.execute("SELECT inventory_id FROM inventory")
    inventory_ids = [r[0] for r in cursor.fetchall()]

    if not store_ids or not address_ids or not staff_ids or not inventory_ids:
        raise ValueError("Base Sakila tables (store, address, staff, inventory) must contain existing records.")

    return store_ids, address_ids, staff_ids, inventory_ids

def generate_customers(cursor, conn, store_ids, address_ids):
    """Generate synthetic customers up to TARGET_CUSTOMERS."""
    cursor.execute("SELECT COUNT(*) FROM customer")
    current_count = cursor.fetchone()[0]
    needed = TARGET_CUSTOMERS - current_count

    if needed <= 0:
        print(f"Customer table already has {current_count} rows. Skipping customer insertion.")
        cursor.execute("SELECT customer_id FROM customer")
        return [r[0] for r in cursor.fetchall()]

    print(f"Generating {needed} new customer records...")
    insert_sql = """
        INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """

    data = []
    for _ in range(needed):
        store_id = random.choice(store_ids)
        first_name = fake.first_name()[:45]
        last_name = fake.last_name()[:45]
        email = f"{first_name.lower()}.{last_name.lower()}@{fake.free_email_domain()}"[:50]
        address_id = random.choice(address_ids)
        active = 1 if random.random() < 0.95 else 0
        create_date = fake.date_time_between(start_date='-3y', end_date='-1y')
        
        data.append((store_id, first_name, last_name, email, address_id, active, create_date))

        if len(data) >= BATCH_SIZE:
            cursor.executemany(insert_sql, data)
            conn.commit()
            data = []

    if data:
        cursor.executemany(insert_sql, data)
        conn.commit()

    cursor.execute("SELECT customer_id FROM customer")
    return [r[0] for r in cursor.fetchall()]

def generate_rentals_and_payments(cursor, conn, customer_ids, staff_ids, inventory_ids):
    """Generate skewed rentals and matching payments."""
    cursor.execute("SELECT COUNT(*) FROM rental")
    current_rentals = cursor.fetchone()[0]
    needed_rentals = TARGET_RENTALS - current_rentals

    if needed_rentals <= 0:
        print(f"Rental table already has {current_rentals} rows. Skipping rental/payment insertion.")
        return

    print(f"Generating {needed_rentals} rentals and payments with Pareto data skew...")

    # Data Skew: Use a Pareto/Power-law distribution for active customers
    num_customers = len(customer_ids)
    weights = np.random.pareto(a=1.5, size=num_customers) + 1
    probabilities = weights / np.sum(weights)

    # Use INSERT IGNORE to safely handle duplicate timestamp collisions
    rental_insert_sql = """
        INSERT IGNORE INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
        VALUES (%s, %s, %s, %s, %s, %s)
    """

    payment_insert_sql = """
        INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
        VALUES (%s, %s, %s, %s, %s)
    """

    rentals_batch = []
    
    # Temporarily disable foreign key checks for batch execution speed
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
    cursor.execute("SET UNIQUE_CHECKS = 0;")

    for i in range(needed_rentals):
        customer_id = int(np.random.choice(customer_ids, p=probabilities))
        staff_id = random.choice(staff_ids)
        inventory_id = random.choice(inventory_ids)

        # Ensure distinct seconds across dates to prevent datetime truncation collisions
        base_date = fake.date_time_between(start_date='-2y', end_date='now')
        rental_date = base_date.replace(second=(i % 60))
        
        rental_days = random.choices([2, 3, 5, 7, 10], weights=[0.2, 0.4, 0.2, 0.1, 0.1])[0]
        return_date = rental_date + timedelta(days=rental_days)
        last_update = return_date

        rentals_batch.append((rental_date, inventory_id, customer_id, return_date, staff_id, last_update))

        if len(rentals_batch) >= BATCH_SIZE:
            cursor.executemany(rental_insert_sql, rentals_batch)
            conn.commit()
            
            # Fetch successfully inserted rental_ids for matching payments
            inserted_count = cursor.rowcount
            if inserted_count > 0:
                cursor.execute(
                    "SELECT rental_id, customer_id, staff_id, rental_date FROM rental ORDER BY rental_id DESC LIMIT %s", 
                    (inserted_count,)
                )
                inserted_rentals = cursor.fetchall()
                
                payments_batch = []
                for r_id, c_id, s_id, r_date in inserted_rentals:
                    base_amount = random.choices([0.99, 2.99, 4.99, 7.99], weights=[0.2, 0.5, 0.2, 0.1])[0]
                    payment_date = r_date + timedelta(hours=random.randint(1, 48))
                    payments_batch.append((c_id, s_id, r_id, base_amount, payment_date))

                cursor.executemany(payment_insert_sql, payments_batch)
                conn.commit()

            rentals_batch = []
            print(f"Processed batch ending at iteration {i + 1}/{needed_rentals}...")

    if rentals_batch:
        cursor.executemany(rental_insert_sql, rentals_batch)
        conn.commit()
        
        inserted_count = cursor.rowcount
        if inserted_count > 0:
            cursor.execute(
                "SELECT rental_id, customer_id, staff_id, rental_date FROM rental ORDER BY rental_id DESC LIMIT %s", 
                (inserted_count,)
            )
            inserted_rentals = cursor.fetchall()
            
            payments_batch = []
            for r_id, c_id, s_id, r_date in inserted_rentals:
                base_amount = random.choices([0.99, 2.99, 4.99, 7.99], weights=[0.2, 0.5, 0.2, 0.1])[0]
                payment_date = r_date + timedelta(hours=random.randint(1, 48))
                payments_batch.append((c_id, s_id, r_id, base_amount, payment_date))

            cursor.executemany(payment_insert_sql, payments_batch)
            conn.commit()

    # Re-enable checks
    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
    cursor.execute("SET UNIQUE_CHECKS = 1;")
    conn.commit()

def generate_missing_payments(cursor, conn, staff_ids):
    """Generate standalone payments linked to existing rentals to reach TARGET_PAYMENTS."""
    cursor.execute("SELECT COUNT(*) FROM payment")
    current_payments = cursor.fetchone()[0]
    needed_payments = TARGET_PAYMENTS - current_payments

    if needed_payments <= 0:
        print(f"Payment table already has {current_payments} rows. Skipping standalone payment insertion.")
        return

    print(f"Generating {needed_payments} standalone payments to reach target...")

    cursor.execute("SELECT rental_id, customer_id, rental_date FROM rental")
    existing_rentals = cursor.fetchall()

    payment_insert_sql = """
        INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
        VALUES (%s, %s, %s, %s, %s)
    """

    payments_batch = []
    for i in range(needed_payments):
        r_id, c_id, r_date = random.choice(existing_rentals)
        s_id = random.choice(staff_ids)
        base_amount = random.choices([0.99, 2.99, 4.99, 7.99], weights=[0.2, 0.5, 0.2, 0.1])[0]
        payment_date = r_date + timedelta(hours=random.randint(1, 48))
        
        payments_batch.append((c_id, s_id, r_id, base_amount, payment_date))

        if len(payments_batch) >= BATCH_SIZE:
            cursor.executemany(payment_insert_sql, payments_batch)
            conn.commit()
            payments_batch = []

    if payments_batch:
        cursor.executemany(payment_insert_sql, payments_batch)
        conn.commit()

def verify_counts(cursor):
    """Print final record counts."""
    print("\n--- Final Verification ---")
    tables = ['customer', 'rental', 'payment']
    for table in tables:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        print(f"Table '{table}': {count:,} rows")

def main():
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        store_ids, address_ids, staff_ids, inventory_ids = fetch_existing_keys(cursor)
        
        customer_ids = generate_customers(cursor, conn, store_ids, address_ids)
        generate_rentals_and_payments(cursor, conn, customer_ids, staff_ids, inventory_ids)
        generate_missing_payments(cursor, conn, staff_ids)
        
        verify_counts(cursor)
        print("\nSynthetic data generation completed successfully!")

    except Exception as e:
        print(f"\nAn error occurred: {e}")
        if conn:
            conn.rollback()
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

if __name__ == '__main__':
    main()