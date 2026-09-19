PART A: 
Chosen tables: rental, payment, and customer

1. Open MySQL Workbench and connect to your local MySQL server instance.

2. Import the sakila database
- File > Open SQL Script > sakila-db/sakila-data.sql
- File > Open SQL Script > sakila-db/sakila-schema.sql

3. Run alter_schema.sql to prevent errors when generating data
- File > Open SQL Script > data/alter_schema.sql
- Execute (lightning bolt icon)

4. Open command prompt and install python libraries
- pip install mysql-connector-python faker numpy

5. Navigate to data folder and run:
- python generate_synthetic_data.py
- (replace password with your password)

PART B and C:
6. Fill the queries in the queries folder