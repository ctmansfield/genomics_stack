# 2025-10-17 – CTD v2 Pipeline Orchestration & Verification

## Summary
- Adds an idempotent runner to orchestrate:
  1) Base `ctd_report_v2.html` build
  2) DDI patient overlay generation (strict expression-only, patient-scoped via `PGOPTIONS`)
  3) Section injections for Expression Balance and DDI overlay
  4) Final Chromium-to-PDF for the main report
  5) Optional standalone PDF for the DDI overlay
- Introduces a repo-tracked `.env` template for threshold/regex tuning.
- Adds a verification script for artifact presence.

## Paths
- Repo root: `/repos/genomics-stack`
- Outputs: `reports/upload_2/`

## Notes
- Uses `--headless=new` to avoid Chromium “Multiple targets are not supported.”; includes a legacy headless fallback.
- No strict bash flags; explicit checks and messages.
- Scripts avoid calling `exit` to prevent accidental shell termination if sourced.
