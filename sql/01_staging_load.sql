/* =====================================================================
   01_staging_load.sql
   ---------------------------------------------------------------------
   Purpose : Land the raw CSV in pharmacy_staging.pharmacy_sales.
   Design  : Every column is TEXT on purpose. The staging layer never
             rejects a row because of a bad type: type problems are
             found by 02_data_quality_checks.sql and fixed in
             03_clean_transform.sql, so nothing is lost silently on load.
   Run     : from the repository root, with psql:
               psql -d <db> -f sql/01_staging_load.sql
             (\copy reads the file from the client machine, so it works
              against a managed/cloud PostgreSQL such as Aiven.)
   ===================================================================== */

SET search_path TO pharmacy_staging;

DROP TABLE IF EXISTS pharmacy_sales;

CREATE TABLE pharmacy_sales (
    order_id               TEXT,
    order_date             TEXT,
    order_time             TEXT,
    customer_id            TEXT,
    customer_gender        TEXT,
    customer_age           TEXT,
    city                   TEXT,
    branch                 TEXT,
    channel                TEXT,
    product_id             TEXT,
    product_name           TEXT,
    brand                  TEXT,
    category               TEXT,
    subcategory            TEXT,
    dosage_form            TEXT,
    requires_prescription  TEXT,
    list_price_kes         TEXT,
    unit_price_kes         TEXT,
    unit_cost_kes          TEXT,
    quantity               TEXT,
    discount_pct           TEXT,
    total_amount_kes       TEXT,
    delivery_fee_kes       TEXT,
    gross_profit_kes       TEXT,
    payment_method         TEXT,
    customer_rating        TEXT,
    loaded_at              TIMESTAMPTZ DEFAULT now()
);

\copy pharmacy_sales (order_id, order_date, order_time, customer_id, customer_gender, customer_age, city, branch, channel, product_id, product_name, brand, category, subcategory, dosage_form, requires_prescription, list_price_kes, unit_price_kes, unit_cost_kes, quantity, discount_pct, total_amount_kes, delivery_fee_kes, gross_profit_kes, payment_method, customer_rating) FROM 'data/raw/pharmacy_sales.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- Load confirmation (expected: 6,000 rows)
SELECT COUNT(*) AS staged_rows FROM pharmacy_sales;
