# Data Dictionary

Reference for every table and view in the pipeline. Currency is Kenyan Shillings (KES).

- [1. Raw source: `pharmacy_sales.csv`](#1-raw-source-pharmacy_salescsv)
- [2. Fact table: `clean_pharmacy.clean_pharmacy`](#2-fact-table-clean_pharmacyclean_pharmacy)
- [3. Reporting views](#3-reporting-views)
- [4. KPI definitions](#4-kpi-definitions)

---

## 1. Raw source: `pharmacy_sales.csv`

| Property | Value |
|---|---|
| Rows | 6,000 (one row per order line) |
| Columns | 26 |
| Period | 1 Jan 2026 – 30 Sep 2026 (273 days) |
| Grain key | `order_id` (unique, no duplicates) |
| Distinct customers | 1,724 |
| Distinct products | 189 across 9 categories |
| Branches / cities | 11 branches (incl. an `Online` fulfilment branch) in 5 cities |

| # | Column | Raw type | Description | Example |
|---|---|---|---|---|
| 1 | `order_id` | text | Unique order-line identifier | `ORD-100000` |
| 2 | `order_date` | date (ISO) | Date of the transaction | `2026-01-01` |
| 3 | `order_time` | time (HH:MM) | Time of the transaction, trading hours 08:00–20:59 | `08:35` |
| 4 | `customer_id` | text | Customer identifier | `CUS00143` |
| 5 | `customer_gender` | text | `Female` / `Male`, captured at the till | `Male` |
| 6 | `customer_age` | integer | Age in years, captured at the till | `31` |
| 7 | `city` | text | City of the fulfilling branch | `Nairobi` |
| 8 | `branch` | text | Fulfilling branch | `Westlands` |
| 9 | `channel` | text | `In-store`, `Online`, `App` | `App` |
| 10 | `product_id` | text | Product identifier | `PRD0180` |
| 11 | `product_name` | text | Product description incl. pack size | `Postinor 2 Tablets 2's` |
| 12 | `brand` | text | Manufacturer brand (kept in staging only) | `Postinor` |
| 13 | `category` | text | One of 9 product categories | `Family Planning` |
| 14 | `subcategory` | text | Product sub-category | `Emergency Contraception` |
| 15 | `dosage_form` | text | 29 forms (Tablet, Liquid, Cream, Device …) | `Tablet` |
| 16 | `requires_prescription` | boolean text | `True` = prescription-only (Rx) | `False` |
| 17 | `list_price_kes` | integer | Recommended retail price | `208` |
| 18 | `unit_price_kes` | decimal | Actual shelf price charged per unit | `214.0` |
| 19 | `unit_cost_kes` | decimal | Landed cost per unit | `131.04` |
| 20 | `quantity` | integer | Units on the line (1–5) | `4` |
| 21 | `discount_pct` | decimal | Discount applied: 0, 5, 10, 15, 18, 20 or 25 | `5.0` |
| 22 | `total_amount_kes` | decimal | Net line revenue = `unit_price × quantity × (1 − discount/100)` | `813.2` |
| 23 | `delivery_fee_kes` | decimal | Delivery charge (Online/App only; 0 in-store). **Not** part of revenue | `300.0` |
| 24 | `gross_profit_kes` | decimal | `total_amount − unit_cost × quantity` (can be negative) | `289.04` |
| 25 | `payment_method` | text | `M-Pesa`, `Card`, `Cash`, `Insurance` | `Insurance` |
| 26 | `customer_rating` | decimal | 1–5 star rating; blank when the customer did not rate | `4.0` |

### Data-quality profile (from `sql/02_data_quality_checks.sql`)

| Check | Result | Treatment |
|---|---|---|
| Duplicate `order_id` | 0 | Primary key added on the clean table to keep it that way |
| Exact duplicate rows | 0 | De-duplication logic kept for future loads |
| Missing values | Only `customer_rating`: 1,546 rows (25.77%) | Left as `NULL`; averages use rated lines only |
| Type conformance (dates, times, numerics, booleans) | 0 failures | Cast to proper types |
| Untrimmed whitespace | 0 | `TRIM` applied defensively |
| Out-of-range quantity / price / cost / discount / age / rating | 0 | Enforced with `CHECK` constraints |
| In-store lines carrying a delivery fee | 0 | Delivery fee kept as a separate column |
| `total_amount_kes` recomputation | 0 mismatches | Source arithmetic trusted |
| `gross_profit_kes` recomputation | 0 mismatches | Source arithmetic trusted |
| Loss-making lines (`gross_profit < 0`) | 203 | **Kept**: real business events, analysed in Q6–Q7 |
| `product_id` → one name / category | 0 violations | Product attributes safe to group by |
| `branch` → one city | 0 violations | Branch → city hierarchy is clean |
| `customer_id` → consistent gender / age / city | **1,530 customers inconsistent** | Customer view takes attributes from the most recent order |

---

## 2. Fact table: `clean_pharmacy.clean_pharmacy`

Grain: one row per order line. Primary key: `order_id`. Built by `sql/03_clean_transform.sql`.

| Column | Type | Notes |
|---|---|---|
| `order_id` | text **PK** | |
| `order_date` | date | indexed |
| `order_time` | time | |
| `customer_id` | text | indexed |
| `customer_gender` | text | `INITCAP` normalised |
| `customer_age` | int | |
| `city` | text | |
| `branch` | text | indexed |
| `channel` | text | |
| `product_id` | text | indexed |
| `product_name` | text | |
| `category` | text | indexed |
| `subcategory` | text | |
| `dosage_form` | text | |
| `requires_prescription` | boolean | |
| `list_price_kes` | numeric(12,2) | |
| `unit_price_kes` | numeric(12,2) | |
| `unit_cost_kes` | numeric(12,2) | |
| `quantity` | int | `CHECK > 0` |
| `discount_pct` | numeric(5,2) | `CHECK 0–100` |
| `total_amount_kes` | numeric(12,2) | revenue |
| `delivery_fee_kes` | numeric(12,2) | |
| `gross_profit_kes` | numeric(12,2) | |
| `payment_method` | text | |
| `customer_rating` | numeric(2,1) | nullable, `CHECK 1–5` |
| `order_year` | int | **derived** |
| `order_month` | int | **derived** 1–12 |
| `order_month_name` | text | **derived** e.g. `January` |
| `day_of_week_num` | int | **derived** 0 = Sunday … 6 = Saturday |
| `day_of_week` | text | **derived** e.g. `Monday` |
| `order_hour` | int | **derived** 8–20 |
| `profit_margin_pct` | numeric | **derived** line margin % |

---

## 3. Reporting views

All views live in the `clean_pharmacy` schema and are defined in `sql/04_analytics_views.sql`.

| View | Grain | Rows | Columns |
|---|---|---|---|
| `v_pharmacy_daily_sales` | date | 273 | `order_date, order_year, order_month, order_month_name, day_of_week_num, day_of_week, total_orders, units_sold, total_revenue, total_profit, profit_margin_pct, average_order_value` |
| `v_branch_performance` | branch | 11 | `branch, total_orders, unique_customers, units_sold, total_revenue, total_profit, profit_margin_pct, average_order_value, average_rating` |
| `v_city_performance` | city | 5 | `city, unique_customers, total_orders, units_sold, total_revenue, total_profit, profit_margin_pct, average_order_value, average_rating` |
| `v_channel_performance` | channel | 3 | `channel, total_orders, unique_customers, units_sold, total_revenue, total_profit, profit_margin_pct, average_order_value, average_rating` |
| `v_category_performance` | category | 9 | `category, units_sold, transaction_count, total_sales, total_profit, profit_margin_pct, average_rating` |
| `v_product_performance` | product | 189 | `product_id, product_name, category, subcategory, dosage_form, units_sold, transaction_count, total_sales, total_profit, profit_margin_pct, average_rating` |
| `v_product_branch_performance` | product × branch | 1,841 | `branch, product_id, product_name, category, units_sold, transaction_count, total_revenue, total_profit, profit_margin_pct, average_rating` |
| `v_customer_performance` | customer | 1,724 | `customer_id, customer_gender, customer_age, city, total_orders, total_units, total_spend, average_order_value, average_rating` |
| `v_product_priority` | product | 189 | all product metrics + `management_priority` |

### `management_priority` logic

Products are placed in a 2×2 matrix using the portfolio **median** revenue and **median** margin as cut-offs:

| | Margin ≥ median | Margin < median |
|---|---|---|
| **Revenue ≥ median** | `Star - protect & grow` | `Volume driver - review pricing` |
| **Revenue < median** | `Niche - promote` | `Underperformer - review range` |

---

## 4. KPI definitions

| KPI | Formula | Value (Jan–Sep 2026) |
|---|---|---|
| Total revenue | `SUM(total_amount_kes)` | KES 14,303,385.95 |
| Total orders | `COUNT(DISTINCT order_id)` | 6,000 |
| Units sold | `SUM(quantity)` | 14,059 |
| Gross profit | `SUM(gross_profit_kes)` | KES 3,502,171.01 |
| Profit margin % | `SUM(gross_profit) / SUM(revenue) × 100` | 24.48% |
| Average order value | `SUM(revenue) / COUNT(DISTINCT order_id)` | KES 2,383.90 |
| Average rating | `AVG(customer_rating)` over rated lines | 3.98 / 5 |
| Delivery fees (excluded from revenue) | `SUM(delivery_fee_kes)` | KES 461,850 |
