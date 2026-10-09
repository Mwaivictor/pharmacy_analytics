/* =====================================================================
   00_create_schemas.sql
   ---------------------------------------------------------------------
   Purpose : Create the two schemas that separate the layers of the
             pipeline.
               pharmacy_staging -> raw landing zone (text, untouched)
               clean_pharmacy   -> typed, validated, enriched table
                                   + reporting views consumed by Power BI
   Target  : PostgreSQL 14+ (built on PostgreSQL 16, hosted on Aiven)
   Run     : psql -d <db> -f sql/00_create_schemas.sql
   ===================================================================== */

CREATE SCHEMA IF NOT EXISTS pharmacy_staging;
CREATE SCHEMA IF NOT EXISTS clean_pharmacy;

COMMENT ON SCHEMA pharmacy_staging IS
    'Raw landing zone: pharmacy_sales.csv loaded as-is, every column TEXT.';
COMMENT ON SCHEMA clean_pharmacy IS
    'Typed and validated sales table plus the analytical views used by Power BI.';
