#!/usr/bin/env bash
# run_pipeline.sh - Build the whole SQL layer on macOS / Linux.
#
# Usage (from the repository root):
#   export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=pharmacy PGPASSWORD=...
#   # For Aiven / any managed Postgres also: export PGSSLMODE=require
#   bash scripts/run_pipeline.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for f in sql/00_create_schemas.sql \
         sql/01_staging_load.sql \
         sql/02_data_quality_checks.sql \
         sql/03_clean_transform.sql \
         sql/04_analytics_views.sql \
         sql/05_view_validation.sql; do
  echo -e "\n==> Running $f"
  psql -v ON_ERROR_STOP=1 -f "$f"
done
echo -e "\nPipeline complete. Open powerbi/PHARMACY_ANALYTICS.pbix and refresh."
