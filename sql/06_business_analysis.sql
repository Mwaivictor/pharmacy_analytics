/* =====================================================================
   06_business_analysis.sql
   ---------------------------------------------------------------------
   Purpose : Answer the business questions behind the dashboard with
             SQL alone. Each query is numbered Q1..Q12 and referenced in
             the README's "Key findings" section.
   Techniques shown: CTEs, window functions (LAG, SUM OVER, RANK,
             NTILE, PERCENT_RANK), FILTER aggregates, CASE banding,
             PERCENTILE_CONT, GROUPING SETS, conditional pivoting.
   ===================================================================== */

SET search_path TO clean_pharmacy;

-- ---------------------------------------------------------------------
-- Q1. Headline KPIs (the Executive Overview cards, computed correctly
--     as ratios of totals)
-- ---------------------------------------------------------------------
SELECT
    SUM(total_amount_kes)                                              AS total_revenue_kes,
    COUNT(DISTINCT order_id)                                           AS total_orders,
    SUM(quantity)                                                      AS units_sold,
    SUM(gross_profit_kes)                                              AS gross_profit_kes,
    ROUND(100 * SUM(gross_profit_kes) / SUM(total_amount_kes), 2)      AS profit_margin_pct,
    ROUND(SUM(total_amount_kes) / COUNT(DISTINCT order_id), 2)         AS average_order_value_kes,
    COUNT(DISTINCT customer_id)                                        AS unique_customers,
    COUNT(DISTINCT product_id)                                         AS products_sold,
    ROUND(AVG(customer_rating), 2)                                     AS average_rating,
    SUM(delivery_fee_kes)                                              AS delivery_fees_collected_kes
FROM clean_pharmacy;

-- ---------------------------------------------------------------------
-- Q2. Month-over-month revenue growth and running total (LAG, SUM OVER)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT order_month, order_month_name,
           SUM(total_revenue) AS revenue,
           SUM(total_profit)  AS profit,
           SUM(total_orders)  AS orders
    FROM v_pharmacy_daily_sales
    GROUP BY order_month, order_month_name
)
SELECT
    order_month,
    order_month_name,
    revenue,
    orders,
    ROUND(100 * profit / revenue, 2)                                           AS margin_pct,
    ROUND(100 * (revenue - LAG(revenue) OVER w) / LAG(revenue) OVER w, 2)      AS mom_growth_pct,
    SUM(revenue) OVER (ORDER BY order_month)                                   AS ytd_revenue
FROM monthly
WINDOW w AS (ORDER BY order_month)
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- Q3. Branch league table with rank and share of revenue
-- ---------------------------------------------------------------------
SELECT
    RANK() OVER (ORDER BY total_revenue DESC)                          AS revenue_rank,
    branch,
    total_revenue,
    ROUND(100 * total_revenue / SUM(total_revenue) OVER (), 2)         AS revenue_share_pct,
    profit_margin_pct,
    RANK() OVER (ORDER BY profit_margin_pct DESC)                      AS margin_rank,
    average_order_value,
    average_rating
FROM v_branch_performance
ORDER BY revenue_rank;

-- ---------------------------------------------------------------------
-- Q4. Pareto (80/20) analysis: how many products make 80% of revenue?
-- ---------------------------------------------------------------------
WITH ranked AS (
    SELECT product_id, product_name, category, total_sales,
           SUM(total_sales) OVER (ORDER BY total_sales DESC, product_id)
             / SUM(total_sales) OVER ()                                AS cumulative_share,
           ROW_NUMBER() OVER (ORDER BY total_sales DESC, product_id)   AS product_rank
    FROM v_product_performance
)
SELECT
    COUNT(*) FILTER (WHERE cumulative_share <= 0.80) + 1               AS products_for_80pct_revenue,
    COUNT(*)                                                           AS total_products,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE cumulative_share <= 0.80) + 1)
          / COUNT(*), 1)                                               AS pct_of_catalogue
FROM ranked;

-- ---------------------------------------------------------------------
-- Q5. Top 3 products inside every category (RANK partitioned)
-- ---------------------------------------------------------------------
SELECT category, category_rank, product_name, total_sales, profit_margin_pct
FROM (
    SELECT category, product_name, total_sales, profit_margin_pct,
           RANK() OVER (PARTITION BY category ORDER BY total_sales DESC) AS category_rank
    FROM v_product_performance
) r
WHERE category_rank <= 3
ORDER BY category, category_rank;

-- ---------------------------------------------------------------------
-- Q6. Discount effectiveness: does discounting buy volume, and what
--     does it cost in margin?
-- ---------------------------------------------------------------------
SELECT
    discount_pct,
    COUNT(*)                                                           AS order_lines,
    ROUND(AVG(quantity), 2)                                            AS avg_units_per_line,
    SUM(total_amount_kes)                                              AS revenue,
    ROUND(100 * SUM(gross_profit_kes) / SUM(total_amount_kes), 2)      AS margin_pct,
    COUNT(*) FILTER (WHERE gross_profit_kes < 0)                       AS loss_making_lines,
    SUM(gross_profit_kes) FILTER (WHERE gross_profit_kes < 0)          AS losses_kes
FROM clean_pharmacy
GROUP BY discount_pct
ORDER BY discount_pct;

-- ---------------------------------------------------------------------
-- Q7. Loss-making lines: where is margin leaking?
-- ---------------------------------------------------------------------
SELECT
    category,
    COUNT(*)                                                           AS loss_lines,
    SUM(gross_profit_kes)                                              AS total_loss_kes,
    ROUND(AVG(discount_pct), 1)                                        AS avg_discount_on_loss_lines
FROM clean_pharmacy
WHERE gross_profit_kes < 0
GROUP BY category
ORDER BY total_loss_kes;

-- ---------------------------------------------------------------------
-- Q8. Channel x payment method mix (conditional pivot with FILTER)
-- ---------------------------------------------------------------------
SELECT
    channel,
    COUNT(*)                                                           AS order_lines,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_method = 'M-Pesa')    / COUNT(*), 1) AS mpesa_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_method = 'Card')      / COUNT(*), 1) AS card_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_method = 'Cash')      / COUNT(*), 1) AS cash_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_method = 'Insurance') / COUNT(*), 1) AS insurance_pct,
    SUM(delivery_fee_kes)                                              AS delivery_fees_kes
FROM clean_pharmacy
GROUP BY ROLLUP (channel)
ORDER BY channel NULLS LAST;

-- ---------------------------------------------------------------------
-- Q9. Prescription (Rx) vs over-the-counter (OTC) economics
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN requires_prescription THEN 'Prescription (Rx)' ELSE 'Over the counter (OTC)' END AS product_type,
    COUNT(*)                                                           AS order_lines,
    SUM(total_amount_kes)                                              AS revenue,
    ROUND(100 * SUM(total_amount_kes) / SUM(SUM(total_amount_kes)) OVER (), 2) AS revenue_share_pct,
    ROUND(100 * SUM(gross_profit_kes) / SUM(total_amount_kes), 2)      AS margin_pct,
    ROUND(AVG(total_amount_kes), 2)                                    AS avg_line_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_method = 'Insurance') / COUNT(*), 1) AS paid_by_insurance_pct
FROM clean_pharmacy
GROUP BY requires_prescription;

-- ---------------------------------------------------------------------
-- Q10. Customer value segmentation (RFM-style with NTILE)
--      Recency measured against the last date in the data set.
-- ---------------------------------------------------------------------
WITH rfm AS (
    SELECT
        customer_id,
        (SELECT MAX(order_date) FROM clean_pharmacy) - MAX(order_date)  AS recency_days,
        COUNT(DISTINCT order_id)                                       AS frequency,
        SUM(total_amount_kes)                                          AS monetary
    FROM clean_pharmacy
    GROUP BY customer_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,   -- 4 = most recent
           NTILE(4) OVER (ORDER BY frequency)         AS f_score,
           NTILE(4) OVER (ORDER BY monetary)          AS m_score
    FROM rfm
),
segmented AS (
    SELECT *,
           CASE
               WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '1. Champions'
               WHEN f_score >= 3 AND m_score >= 3                  THEN '2. Loyal - at risk'
               WHEN r_score >= 3                                   THEN '3. Recent / developing'
               ELSE                                                     '4. Lapsing'
           END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*)                                                           AS customers,
    ROUND(AVG(frequency), 1)                                           AS avg_orders,
    ROUND(AVG(monetary), 0)                                            AS avg_spend_kes,
    SUM(monetary)                                                      AS segment_revenue_kes,
    ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)         AS revenue_share_pct
FROM segmented
GROUP BY segment
ORDER BY segment;

-- ---------------------------------------------------------------------
-- Q11. Demand heat-map: orders by weekday x time-of-day band
--      (staffing and stock-replenishment planning)
--      Bands have different lengths (4, 4 and 5 trading hours), so they
--      are compared as AVERAGE LINES PER HOUR, not raw counts.
-- ---------------------------------------------------------------------
SELECT
    day_of_week_num,
    day_of_week,
    ROUND(COUNT(*) FILTER (WHERE order_hour BETWEEN 8  AND 11) / 4.0, 1) AS morning_08_11_per_hr,
    ROUND(COUNT(*) FILTER (WHERE order_hour BETWEEN 12 AND 15) / 4.0, 1) AS afternoon_12_15_per_hr,
    ROUND(COUNT(*) FILTER (WHERE order_hour BETWEEN 16 AND 20) / 5.0, 1) AS evening_16_20_per_hr,
    COUNT(*)                                                             AS total_lines
FROM clean_pharmacy
GROUP BY day_of_week_num, day_of_week
ORDER BY day_of_week_num;

-- Q11b. Hour-of-day profile across the whole period
SELECT order_hour,
       COUNT(*)                                                  AS order_lines,
       RANK() OVER (ORDER BY COUNT(*) DESC)                      AS busyness_rank
FROM clean_pharmacy
GROUP BY order_hour
ORDER BY order_hour;

-- ---------------------------------------------------------------------
-- Q12. Product priority matrix summary (from v_product_priority)
-- ---------------------------------------------------------------------
SELECT
    management_priority,
    COUNT(*)                                                           AS products,
    SUM(total_sales)                                                   AS revenue_kes,
    ROUND(100 * SUM(total_sales) / SUM(SUM(total_sales)) OVER (), 1)   AS revenue_share_pct,
    ROUND(100 * SUM(total_profit) / SUM(total_sales), 2)               AS margin_pct
FROM v_product_priority
GROUP BY management_priority
ORDER BY revenue_kes DESC;

-- ---------------------------------------------------------------------
-- Q13. Customer demographics by age band and gender (GROUPING SETS)
--      Uses transaction-level demographics, as captured at the till.
-- ---------------------------------------------------------------------
SELECT
    COALESCE(age_band, 'All ages')                                     AS age_band,
    COALESCE(customer_gender, 'All')                                   AS gender,
    COUNT(*)                                                           AS order_lines,
    SUM(total_amount_kes)                                              AS revenue_kes,
    ROUND(AVG(total_amount_kes), 2)                                    AS avg_line_value
FROM (
    SELECT *,
           CASE WHEN customer_age < 25 THEN '18-24'
                WHEN customer_age < 35 THEN '25-34'
                WHEN customer_age < 45 THEN '35-44'
                WHEN customer_age < 55 THEN '45-54'
                ELSE '55+' END AS age_band
    FROM clean_pharmacy
) a
GROUP BY GROUPING SETS ((age_band), (customer_gender), ())
ORDER BY age_band NULLS LAST, gender;
