/* =====================================================================
   02_data_quality_checks.sql
   ---------------------------------------------------------------------
   Purpose : Profile the raw staging table BEFORE cleaning, so every
             cleaning rule in 03_clean_transform.sql is backed by
             evidence. Each query returns a small result set that can be
             read top to bottom as a data-quality report.
   Layer   : pharmacy_staging (read-only)
   ===================================================================== */

SET search_path TO pharmacy_staging;

-- ---------------------------------------------------------------------
-- DQ-01  Volume and grain
--        One row should equal one order line, keyed by order_id.
-- ---------------------------------------------------------------------
SELECT COUNT(*)                         AS total_rows,
       COUNT(DISTINCT order_id)         AS distinct_order_ids,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids,
       COUNT(DISTINCT customer_id)      AS distinct_customers,
       COUNT(DISTINCT product_id)       AS distinct_products,
       MIN(order_date)                  AS first_order_date,
       MAX(order_date)                  AS last_order_date
FROM pharmacy_sales;

-- ---------------------------------------------------------------------
-- DQ-02  Exact duplicate rows (all business columns identical)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS exact_duplicate_rows
FROM (
    SELECT order_id, order_date, order_time, customer_id, product_id,
           quantity, total_amount_kes,
           COUNT(*) OVER (PARTITION BY order_id, order_date, order_time,
                                       customer_id, product_id, quantity,
                                       total_amount_kes) AS n
    FROM pharmacy_sales
) d
WHERE n > 1;

-- ---------------------------------------------------------------------
-- DQ-03  Missing values per column (NULL or blank after trimming)
-- ---------------------------------------------------------------------
SELECT column_name, missing_count,
       ROUND(100.0 * missing_count / total, 2) AS missing_pct
FROM (
    SELECT COUNT(*) AS total,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(order_id), '') IS NULL)          AS order_id,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(order_date), '') IS NULL)        AS order_date,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_id), '') IS NULL)       AS customer_id,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(branch), '') IS NULL)            AS branch,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(product_id), '') IS NULL)        AS product_id,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(unit_price_kes), '') IS NULL)    AS unit_price_kes,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(quantity), '') IS NULL)          AS quantity,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(total_amount_kes), '') IS NULL)  AS total_amount_kes,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(payment_method), '') IS NULL)    AS payment_method,
           COUNT(*) FILTER (WHERE NULLIF(TRIM(customer_rating), '') IS NULL)   AS customer_rating
    FROM pharmacy_sales
) s
CROSS JOIN LATERAL (VALUES
    ('order_id', order_id), ('order_date', order_date), ('customer_id', customer_id),
    ('branch', branch), ('product_id', product_id), ('unit_price_kes', unit_price_kes),
    ('quantity', quantity), ('total_amount_kes', total_amount_kes),
    ('payment_method', payment_method), ('customer_rating', customer_rating)
) v(column_name, missing_count)
ORDER BY missing_count DESC;

-- ---------------------------------------------------------------------
-- DQ-04  Type conformance: values that would fail a cast
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_date !~ '^\d{4}-\d{2}-\d{2}$')                 AS bad_dates,
    COUNT(*) FILTER (WHERE order_time !~ '^\d{2}:\d{2}(:\d{2})?$')              AS bad_times,
    COUNT(*) FILTER (WHERE customer_age !~ '^\d+$')                            AS bad_ages,
    COUNT(*) FILTER (WHERE quantity !~ '^\d+$')                                AS bad_quantities,
    COUNT(*) FILTER (WHERE unit_price_kes !~ '^-?\d+(\.\d+)?$')                AS bad_unit_prices,
    COUNT(*) FILTER (WHERE total_amount_kes !~ '^-?\d+(\.\d+)?$')              AS bad_totals,
    COUNT(*) FILTER (WHERE LOWER(requires_prescription) NOT IN ('true','false')) AS bad_rx_flags
FROM pharmacy_sales;

-- ---------------------------------------------------------------------
-- DQ-05  Categorical domains: spot typos / casing / stray whitespace
-- ---------------------------------------------------------------------
SELECT 'channel' AS field, channel AS value, COUNT(*) AS n FROM pharmacy_sales GROUP BY channel
UNION ALL
SELECT 'payment_method', payment_method, COUNT(*) FROM pharmacy_sales GROUP BY payment_method
UNION ALL
SELECT 'customer_gender', customer_gender, COUNT(*) FROM pharmacy_sales GROUP BY customer_gender
UNION ALL
SELECT 'city', city, COUNT(*) FROM pharmacy_sales GROUP BY city
UNION ALL
SELECT 'category', category, COUNT(*) FROM pharmacy_sales GROUP BY category
ORDER BY field, n DESC;

SELECT COUNT(*) AS values_with_untrimmed_whitespace
FROM pharmacy_sales
WHERE branch <> TRIM(branch) OR city <> TRIM(city) OR channel <> TRIM(channel)
   OR product_name <> TRIM(product_name) OR category <> TRIM(category);

-- ---------------------------------------------------------------------
-- DQ-06  Business-rule ranges
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE quantity::INT <= 0)                              AS non_positive_qty,
    COUNT(*) FILTER (WHERE unit_price_kes::NUMERIC <= 0)                    AS non_positive_price,
    COUNT(*) FILTER (WHERE unit_cost_kes::NUMERIC  <= 0)                    AS non_positive_cost,
    COUNT(*) FILTER (WHERE discount_pct::NUMERIC NOT BETWEEN 0 AND 100)     AS discount_out_of_range,
    COUNT(*) FILTER (WHERE customer_age::INT NOT BETWEEN 0 AND 110)         AS implausible_age,
    COUNT(*) FILTER (WHERE customer_rating IS NOT NULL
                       AND customer_rating::NUMERIC NOT BETWEEN 1 AND 5)    AS rating_out_of_range,
    COUNT(*) FILTER (WHERE channel = 'In-store'
                       AND delivery_fee_kes::NUMERIC > 0)                   AS instore_with_delivery_fee,
    COUNT(*) FILTER (WHERE gross_profit_kes::NUMERIC < 0)                   AS loss_making_lines
FROM pharmacy_sales;

-- ---------------------------------------------------------------------
-- DQ-07  Arithmetic reconciliation
--        total_amount  = unit_price * quantity * (1 - discount/100)
--        gross_profit  = total_amount - unit_cost * quantity
--        Delivery fee is NOT part of total_amount (it is pass-through).
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE ABS(total_amount_kes::NUMERIC
          - ROUND(unit_price_kes::NUMERIC * quantity::INT
                  * (1 - discount_pct::NUMERIC / 100), 2)) > 0.01)          AS amount_mismatches,
    COUNT(*) FILTER (WHERE ABS(gross_profit_kes::NUMERIC
          - ROUND(total_amount_kes::NUMERIC
                  - unit_cost_kes::NUMERIC * quantity::INT, 2)) > 0.01)      AS profit_mismatches
FROM pharmacy_sales;

-- ---------------------------------------------------------------------
-- DQ-08  Referential consistency of master data inside a flat file
--        A product_id should map to exactly one name/category; a branch
--        should belong to exactly one city.
-- ---------------------------------------------------------------------
SELECT 'product_id -> >1 name/category' AS check_name, COUNT(*) AS violations
FROM (SELECT product_id FROM pharmacy_sales
      GROUP BY product_id
      HAVING COUNT(DISTINCT product_name) > 1 OR COUNT(DISTINCT category) > 1) p
UNION ALL
SELECT 'branch -> >1 city', COUNT(*)
FROM (SELECT branch FROM pharmacy_sales
      GROUP BY branch HAVING COUNT(DISTINCT city) > 1) b
UNION ALL
-- Customer demographics are captured per transaction, not from a master
-- record. This check shows how often the same customer_id carries
-- different gender / age / city values across orders.
SELECT 'customer_id -> inconsistent demographics', COUNT(*)
FROM (SELECT customer_id FROM pharmacy_sales
      GROUP BY customer_id
      HAVING COUNT(DISTINCT customer_gender) > 1
          OR COUNT(DISTINCT customer_age)    > 1
          OR COUNT(DISTINCT city)            > 1) c;
