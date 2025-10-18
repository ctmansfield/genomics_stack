# 2025-10-17 – CTD v2 Pipeline Orchestration & Verification

## Summary
- Adds an idempotent runner to orchestrate:
  1) Base `ctd_report_v2.html` build
  2) DDI patient overlay generation (strict expression-only, patient-scoped via `PGOPTIONS`)
  3) Section injections for Expression Balance and DDI overlay
  4) Final Chromium-to-PDF for the main report
  5) Optional standalone PDF for the DDI overlay
- Introduces a simple, repo-tracked `.env` template for threshold/regex tuning.
- Adds a verification script to assert single-injection, expected CSV headers, and artifact presence.

## Rationale
- Centralizes a multi-step process into one script without embedding HTML in builder scripts.
- Keeps everything idempotent and env-tunable; respects your `PGPORT=55432`, `PGOPTIONS='-c app.patient_upload_id=2'` pattern.
- Avoids brittle `set -euo pipefail`; explicit checks and messages instead.

## Files
- `scripts/reports/run_ctd_report_pipeline.sh` – main orchestrator.
- `scripts/reports/ddi_overlay_pdf.sh` – optional overlay PDF.
- `scripts/reports/verify_upload_2.sh` – post-run checks.
- `config/reports/ctd_overlay.env.example` – config template.
