/* =====================================================================
   03_clean_transform.sql
   ---------------------------------------------------------------------
   Purpose : Build clean_pharmacy.clean_pharmacy, the single typed,
             validated and enriched fact table that every reporting view
             (04_analytics_views.sql) and Power BI read from.

   Cleaning rules (each one traced to a check in 02_data_quality_checks)
     C1  Trim whitespace on every text field; normalise casing of the
         low-cardinality labels (gender, channel, payment method).
     C2  Cast every column to its proper type (DATE, TIME, INT,
         NUMERIC(12,2), BOOLEAN).
     C3  De-duplicate on order_id, keeping the first loaded row.
     C4  Reject rows that break hard business rules
         (quantity <= 0, price/cost <= 0, discount outside 0-100).
     C5  Keep customer_rating NULL when the customer did not rate.
         ~26% of lines are unrated; imputing a value would bias every
         average-rating KPI, so NULL is the honest value.
     C6  Delivery fee is kept as its own column and excluded from
         revenue (it is a pass-through charge, not product sales).

   Enrichment (derived columns used for time intelligence in Power BI)
     order_year, order_month, order_month_name, day_of_week_num (0=Sun),
     day_of_week, order_hour, profit_margin_pct (line-level).

   Note    : `brand` stays in the staging layer. The reporting model is
             product-level, so brand is not carried into the clean table.
   ===================================================================== */

SET search_path TO clean_pharmacy;

DROP TABLE IF EXISTS clean_pharmacy CASCADE;   -- CASCADE drops dependent views; 04 recreates them

CREATE TABLE clean_pharmacy AS
WITH typed AS (
    SELECT
        TRIM(order_id)                                   AS order_id,
        TRIM(order_date)::DATE                           AS order_date,
        TRIM(order_time)::TIME                           AS order_time,
        TRIM(customer_id)                                AS customer_id,
        INITCAP(TRIM(customer_gender))                   AS customer_gender,
        TRIM(customer_age)::INT                          AS customer_age,
        TRIM(city)                                       AS city,
        TRIM(branch)                                     AS branch,
        TRIM(channel)                                    AS channel,
        TRIM(product_id)                                 AS product_id,
        TRIM(product_name)                               AS product_name,
        TRIM(category)                                   AS category,
        TRIM(subcategory)                                AS subcategory,
        TRIM(dosage_form)                                AS dosage_form,
        LOWER(TRIM(requires_prescription))::BOOLEAN      AS requires_prescription,
        TRIM(list_price_kes)::NUMERIC(12,2)              AS list_price_kes,
        TRIM(unit_price_kes)::NUMERIC(12,2)              AS unit_price_kes,
        TRIM(unit_cost_kes)::NUMERIC(12,2)               AS unit_cost_kes,
        TRIM(quantity)::INT                              AS quantity,
        TRIM(discount_pct)::NUMERIC(5,2)                 AS discount_pct,
        TRIM(total_amount_kes)::NUMERIC(12,2)            AS total_amount_kes,
        COALESCE(NULLIF(TRIM(delivery_fee_kes), ''), '0')::NUMERIC(12,2) AS delivery_fee_kes,
        TRIM(gross_profit_kes)::NUMERIC(12,2)            AS gross_profit_kes,
        TRIM(payment_method)                             AS payment_method,
        NULLIF(TRIM(customer_rating), '')::NUMERIC(2,1)  AS customer_rating,
        ROW_NUMBER() OVER (PARTITION BY TRIM(order_id)
                           ORDER BY loaded_at, order_date, order_time) AS rn
    FROM pharmacy_staging.pharmacy_sales
)
SELECT
    order_id, order_date, order_time, customer_id, customer_gender, customer_age,
    city, branch, channel, product_id, product_name, category, subcategory,
    dosage_form, requires_prescription, list_price_kes, unit_price_kes,
    unit_cost_kes, quantity, discount_pct, total_amount_kes, delivery_fee_kes,
    gross_profit_kes, payment_method, customer_rating,

    -- Time-intelligence attributes
    EXTRACT(YEAR  FROM order_date)::INT              AS order_year,
    EXTRACT(MONTH FROM order_date)::INT              AS order_month,
    TRIM(TO_CHAR(order_date, 'Month'))               AS order_month_name,
    EXTRACT(DOW   FROM order_date)::INT              AS day_of_week_num,   -- 0 = Sunday
    TRIM(TO_CHAR(order_date, 'Day'))                 AS day_of_week,
    EXTRACT(HOUR  FROM order_time)::INT              AS order_hour,

    -- Line-level margin (guarded against divide-by-zero)
    ROUND(100 * gross_profit_kes / NULLIF(total_amount_kes, 0), 2) AS profit_margin_pct
FROM typed
WHERE rn = 1                                          -- C3
  AND quantity       > 0                              -- C4
  AND unit_price_kes > 0
  AND unit_cost_kes  > 0
  AND discount_pct BETWEEN 0 AND 100;

-- Constraints document the grain and protect the table on reload
ALTER TABLE clean_pharmacy ADD PRIMARY KEY (order_id);
ALTER TABLE clean_pharmacy
    ADD CONSTRAINT chk_quantity  CHECK (quantity > 0),
    ADD CONSTRAINT chk_discount  CHECK (discount_pct BETWEEN 0 AND 100),
    ADD CONSTRAINT chk_rating    CHECK (customer_rating IS NULL OR customer_rating BETWEEN 1 AND 5);

-- Indexes on the columns the views group and filter by
CREATE INDEX idx_clean_order_date ON clean_pharmacy (order_date);
CREATE INDEX idx_clean_branch     ON clean_pharmacy (branch);
CREATE INDEX idx_clean_product    ON clean_pharmacy (product_id);
CREATE INDEX idx_clean_customer   ON clean_pharmacy (customer_id);
CREATE INDEX idx_clean_category   ON clean_pharmacy (category);

COMMENT ON TABLE clean_pharmacy IS
    'One row per order line. Typed, de-duplicated and enriched copy of pharmacy_staging.pharmacy_sales.';
COMMENT ON COLUMN clean_pharmacy.total_amount_kes  IS 'Net line revenue after discount, excluding delivery fee (KES).';
COMMENT ON COLUMN clean_pharmacy.gross_profit_kes  IS 'total_amount_kes - unit_cost_kes * quantity (KES).';
COMMENT ON COLUMN clean_pharmacy.profit_margin_pct IS 'Line gross margin: gross_profit / total_amount * 100.';
COMMENT ON COLUMN clean_pharmacy.day_of_week_num   IS '0 = Sunday ... 6 = Saturday (PostgreSQL DOW).';

-- ---------------------------------------------------------------------
-- Post-load reconciliation: clean vs staging
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM pharmacy_staging.pharmacy_sales)          AS staged_rows,
    (SELECT COUNT(*) FROM clean_pharmacy)                           AS clean_rows,
    (SELECT COUNT(*) FROM pharmacy_staging.pharmacy_sales)
      - (SELECT COUNT(*) FROM clean_pharmacy)                       AS rows_rejected,
    (SELECT SUM(total_amount_kes) FROM clean_pharmacy)              AS clean_revenue_kes,
    (SELECT SUM(total_amount_kes::NUMERIC)
       FROM pharmacy_staging.pharmacy_sales)                        AS staged_revenue_kes;
