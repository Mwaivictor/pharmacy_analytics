/* =====================================================================
   05_view_validation.sql
   ---------------------------------------------------------------------
   Purpose : Prove the semantic layer is correct before Power BI reads it.
     Part A  Smoke test: preview each view (the original validation set).
     Part B  Reconciliation: every view must roll up to the same
             revenue / profit / units as the clean fact table.
     Part C  Grain tests: each view returns exactly one row per key.
   A healthy run returns status = 'PASS' on every row of Parts B and C.
   ===================================================================== */

SET search_path TO clean_pharmacy;

-- ---------------------------------------------------------------------
-- Part A. Smoke test
-- ---------------------------------------------------------------------
SELECT * FROM v_pharmacy_daily_sales        ORDER BY order_date LIMIT 10;
SELECT * FROM v_product_performance         ORDER BY total_sales DESC LIMIT 10;
SELECT * FROM v_category_performance        ORDER BY total_sales DESC LIMIT 10;
SELECT * FROM v_branch_performance          ORDER BY total_revenue DESC LIMIT 10;
SELECT * FROM v_customer_performance        ORDER BY total_spend DESC LIMIT 10;
SELECT * FROM v_channel_performance         ORDER BY total_revenue DESC LIMIT 10;
SELECT * FROM v_city_performance            ORDER BY total_revenue DESC LIMIT 10;
SELECT * FROM v_product_branch_performance  ORDER BY total_revenue DESC LIMIT 10;
SELECT * FROM v_product_priority            ORDER BY total_sales DESC LIMIT 10;

-- ---------------------------------------------------------------------
-- Part B. Reconciliation against the fact table
-- ---------------------------------------------------------------------
WITH fact AS (
    SELECT SUM(total_amount_kes) AS revenue,
           SUM(gross_profit_kes) AS profit,
           SUM(quantity)         AS units
    FROM clean_pharmacy
),
views AS (
    SELECT 'v_pharmacy_daily_sales' AS view_name, SUM(total_revenue) AS revenue, SUM(total_profit) AS profit, SUM(units_sold) AS units FROM v_pharmacy_daily_sales
    UNION ALL SELECT 'v_branch_performance',         SUM(total_revenue), SUM(total_profit), SUM(units_sold)  FROM v_branch_performance
    UNION ALL SELECT 'v_city_performance',           SUM(total_revenue), SUM(total_profit), SUM(units_sold)  FROM v_city_performance
    UNION ALL SELECT 'v_channel_performance',        SUM(total_revenue), SUM(total_profit), SUM(units_sold)  FROM v_channel_performance
    UNION ALL SELECT 'v_category_performance',       SUM(total_sales),   SUM(total_profit), SUM(units_sold)  FROM v_category_performance
    UNION ALL SELECT 'v_product_performance',        SUM(total_sales),   SUM(total_profit), SUM(units_sold)  FROM v_product_performance
    UNION ALL SELECT 'v_product_branch_performance', SUM(total_revenue), SUM(total_profit), SUM(units_sold)  FROM v_product_branch_performance
    UNION ALL SELECT 'v_customer_performance',       SUM(total_spend),   NULL,              SUM(total_units) FROM v_customer_performance
    UNION ALL SELECT 'v_product_priority',           SUM(total_sales),   SUM(total_profit), SUM(units_sold)  FROM v_product_priority
)
SELECT v.view_name,
       v.revenue, f.revenue AS fact_revenue,
       v.units,   f.units   AS fact_units,
       CASE WHEN v.revenue = f.revenue
             AND v.units   = f.units
             AND (v.profit IS NULL OR v.profit = f.profit)
            THEN 'PASS' ELSE 'FAIL' END AS status
FROM views v CROSS JOIN fact f
ORDER BY v.view_name;

-- ---------------------------------------------------------------------
-- Part C. Grain tests (duplicates would double-count in Power BI)
-- ---------------------------------------------------------------------
SELECT 'v_pharmacy_daily_sales: 1 row per date' AS test,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_date) THEN 'PASS' ELSE 'FAIL' END AS status
FROM v_pharmacy_daily_sales
UNION ALL
SELECT 'v_branch_performance: 1 row per branch',
       CASE WHEN COUNT(*) = COUNT(DISTINCT branch) THEN 'PASS' ELSE 'FAIL' END
FROM v_branch_performance
UNION ALL
SELECT 'v_customer_performance: 1 row per customer',
       CASE WHEN COUNT(*) = COUNT(DISTINCT customer_id) THEN 'PASS' ELSE 'FAIL' END
FROM v_customer_performance
UNION ALL
SELECT 'v_product_performance: 1 row per product',
       CASE WHEN COUNT(*) = COUNT(DISTINCT product_id) THEN 'PASS' ELSE 'FAIL' END
FROM v_product_performance
UNION ALL
SELECT 'v_product_branch_performance: 1 row per product x branch',
       CASE WHEN COUNT(*) = COUNT(DISTINCT (product_id, branch)) THEN 'PASS' ELSE 'FAIL' END
FROM v_product_branch_performance
UNION ALL
SELECT 'v_product_priority: every product tagged',
       CASE WHEN COUNT(*) FILTER (WHERE management_priority IS NULL) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM v_product_priority;
