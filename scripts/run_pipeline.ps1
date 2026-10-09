<#
  run_pipeline.ps1  -  Build the whole SQL layer on Windows.

  Usage (from the repository root, in PowerShell):
      $env:PGHOST="localhost"; $env:PGPORT="5432"; $env:PGUSER="postgres"
      $env:PGDATABASE="pharmacy"; $env:PGPASSWORD="<your password>"
      # For Aiven / any managed Postgres also set:  $env:PGSSLMODE="require"
      .\scripts\run_pipeline.ps1

  Requires psql on PATH (installed with PostgreSQL, e.g.
  C:\Program Files\PostgreSQL\16\bin).
#>
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$steps = @(
    "sql/00_create_schemas.sql",
    "sql/01_staging_load.sql",
    "sql/02_data_quality_checks.sql",
    "sql/03_clean_transform.sql",
    "sql/04_analytics_views.sql",
    "sql/05_view_validation.sql"
)

foreach ($f in $steps) {
    Write-Host "`n==> Running $f" -ForegroundColor Cyan
    psql -v ON_ERROR_STOP=1 -f $f
    if ($LASTEXITCODE -ne 0) { throw "Failed on $f" }
}
Write-Host "`nPipeline complete. Open powerbi/PHARMACY_ANALYTICS.pbix and refresh." -ForegroundColor Green
