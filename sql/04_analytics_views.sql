/* =====================================================================
   04_analytics_views.sql
   ---------------------------------------------------------------------
   Purpose : The semantic layer. Nine views pre-aggregate
             clean_pharmacy.clean_pharmacy at the grain each report
             visual needs, so Power BI imports small, already-correct
             tables instead of re-deriving business logic in DAX.

   KPI definitions (identical in every view, so numbers reconcile):
     total_orders        COUNT(DISTINCT order_id)
     units_sold          SUM(quantity)
     total_revenue /
     total_sales         SUM(total_amount_kes)      -- excl. delivery fee
     total_profit        SUM(gross_profit_kes)
     profit_margin_pct   total_profit / total_revenue * 100
                         (ratio of sums, never an average of line margins)
     average_order_value total_revenue / total_orders
     average_rating      AVG(customer_rating) over rated lines only

   View                          Grain                    Used on page
   ----------------------------- ------------------------ -------------
   v_pharmacy_daily_sales        1 row per calendar day   1, 2
   v_branch_performance          1 row per branch         2
   v_city_performance            1 row per city           2
   v_channel_performance         1 row per channel        1, 2
   v_category_performance        1 row per category       3
   v_product_performance         1 row per product        3
   v_product_branch_performance  1 row per product x branch  1
   v_customer_performance        1 row per customer       (model)
   v_product_priority            1 row per product + action tag  (model)
   ===================================================================== */

SET search_path TO clean_pharmacy;

-- ---------------------------------------------------------------------
-- 1. Daily sales: the time-series backbone (trend, MoM, weekday views)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pharmacy_daily_sales AS
SELECT
    order_date,
    order_year,
    order_month,
    order_month_name,
    day_of_week_num,
    day_of_week,
    COUNT(DISTINCT order_id)                                        AS total_orders,
    SUM(quantity)                                                   AS units_sold,
    SUM(total_amount_kes)                                           AS total_revenue,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(SUM(total_amount_kes) / NULLIF(COUNT(DISTINCT order_id), 0), 2)          AS average_order_value
FROM clean_pharmacy
GROUP BY order_date, order_year, order_month, order_month_name, day_of_week_num, day_of_week;

-- ---------------------------------------------------------------------
-- 2. Branch performance
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_branch_performance AS
SELECT
    branch,
    COUNT(DISTINCT order_id)                                        AS total_orders,
    COUNT(DISTINCT customer_id)                                     AS unique_customers,
    SUM(quantity)                                                   AS units_sold,
    SUM(total_amount_kes)                                           AS total_revenue,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(SUM(total_amount_kes) / NULLIF(COUNT(DISTINCT order_id), 0), 2)          AS average_order_value,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY branch;

-- ---------------------------------------------------------------------
-- 3. Category performance
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_category_performance AS
SELECT
    category,
    SUM(quantity)                                                   AS units_sold,
    COUNT(*)                                                        AS transaction_count,
    SUM(total_amount_kes)                                           AS total_sales,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY category;

-- ---------------------------------------------------------------------
-- 4. Channel performance (In-store / Online / App)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_channel_performance AS
SELECT
    channel,
    COUNT(DISTINCT order_id)                                        AS total_orders,
    COUNT(DISTINCT customer_id)                                     AS unique_customers,
    SUM(quantity)                                                   AS units_sold,
    SUM(total_amount_kes)                                           AS total_revenue,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(SUM(total_amount_kes) / NULLIF(COUNT(DISTINCT order_id), 0), 2)          AS average_order_value,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY channel;

-- ---------------------------------------------------------------------
-- 5. City performance
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_city_performance AS
SELECT
    city,
    COUNT(DISTINCT customer_id)                                     AS unique_customers,
    COUNT(DISTINCT order_id)                                        AS total_orders,
    SUM(quantity)                                                   AS units_sold,
    SUM(total_amount_kes)                                           AS total_revenue,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(SUM(total_amount_kes) / NULLIF(COUNT(DISTINCT order_id), 0), 2)          AS average_order_value,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY city;

-- ---------------------------------------------------------------------
-- 6. Customer performance
--    Demographics are recorded per transaction and are not consistent
--    for the same customer_id (see DQ-08). To keep exactly one row per
--    customer, gender / age / city are taken from the customer's most
--    recent order (a documented, deterministic rule).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_performance AS
WITH latest_profile AS (
    SELECT DISTINCT ON (customer_id)
           customer_id, customer_gender, customer_age, city
    FROM clean_pharmacy
    ORDER BY customer_id, order_date DESC, order_time DESC, order_id DESC
),
spend AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id)                                    AS total_orders,
        SUM(quantity)                                               AS total_units,
        SUM(total_amount_kes)                                       AS total_spend,
        ROUND(SUM(total_amount_kes) / NULLIF(COUNT(DISTINCT order_id), 0), 2)      AS average_order_value,
        ROUND(AVG(customer_rating), 2)                              AS average_rating
    FROM clean_pharmacy
    GROUP BY customer_id
)
SELECT
    p.customer_id,
    p.customer_gender,
    p.customer_age,
    p.city,
    s.total_orders,
    s.total_units,
    s.total_spend,
    s.average_order_value,
    s.average_rating
FROM latest_profile p
JOIN spend s USING (customer_id);

-- ---------------------------------------------------------------------
-- 7. Product x branch performance (assortment by location)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_product_branch_performance AS
SELECT
    branch,
    product_id,
    product_name,
    category,
    SUM(quantity)                                                   AS units_sold,
    COUNT(*)                                                        AS transaction_count,
    SUM(total_amount_kes)                                           AS total_revenue,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY branch, product_id, product_name, category;

-- ---------------------------------------------------------------------
-- 8. Product performance
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_product_performance AS
SELECT
    product_id,
    product_name,
    category,
    subcategory,
    dosage_form,
    SUM(quantity)                                                   AS units_sold,
    COUNT(*)                                                        AS transaction_count,
    SUM(total_amount_kes)                                           AS total_sales,
    SUM(gross_profit_kes)                                           AS total_profit,
    ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)       AS profit_margin_pct,
    ROUND(AVG(customer_rating), 2)                                  AS average_rating
FROM clean_pharmacy
GROUP BY product_id, product_name, category, subcategory, dosage_form;

-- ---------------------------------------------------------------------
-- 9. Product priority: turns product metrics into a management action.
--    Each product is placed in a 2x2 matrix using the portfolio MEDIAN
--    of sales and of margin as the cut-offs (medians resist the skew of
--    a few very high-value SKUs):
--
--                    margin >= median        margin < median
--    sales >= median Star: protect & grow    Volume driver: review pricing
--    sales <  median Niche: promote          Underperformer: review range
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_product_priority AS
WITH product AS (
    SELECT
        product_id,
        product_name,
        category,
        subcategory,
        SUM(quantity)                                               AS units_sold,
        COUNT(*)                                                    AS transaction_count,
        SUM(total_amount_kes)                                       AS total_sales,
        SUM(gross_profit_kes)                                       AS total_profit,
        ROUND(100 * SUM(gross_profit_kes) / NULLIF(SUM(total_amount_kes), 0), 2)   AS profit_margin_pct,
        ROUND(AVG(customer_rating), 2)                              AS average_rating
    FROM clean_pharmacy
    GROUP BY product_id, product_name, category, subcategory
),
cutoffs AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_sales)        AS median_sales,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY profit_margin_pct)  AS median_margin
    FROM product
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.subcategory,
    p.units_sold,
    p.transaction_count,
    p.total_sales,
    p.total_profit,
    p.profit_margin_pct,
    p.average_rating,
    CASE
        WHEN p.total_sales >= c.median_sales AND p.profit_margin_pct >= c.median_margin
            THEN 'Star - protect & grow'
        WHEN p.total_sales >= c.median_sales
            THEN 'Volume driver - review pricing'
        WHEN p.profit_margin_pct >= c.median_margin
            THEN 'Niche - promote'
        ELSE 'Underperformer - review range'
    END                                                             AS management_priority
FROM product p
CROSS JOIN cutoffs c;
