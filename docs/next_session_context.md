# Next-Session Context — Genomics Stack

**Where we left off**
- **Expression Balance** section: export CSVs → HTML body → injected into `ctd_report_v2.html`.
- **DDI Patient Overlay**: CSV includes `include_reason` (`meets_thresholds` / `whitelist`), HTML built, injected into main report.
- PDF rendering via headless Chrome in Docker (`zenika/alpine-chrome:124`).

**Key scripts**
- `scripts/reports/ctd_expr_balance_export.sh`
- `scripts/reports/ctd_expr_balance_html.sh`
- `scripts/reports/ctd_ddi_patient_overlay.sh` (knobs: `MIN_TOTAL`, `MIN_GENES`, `BAL_THR`, `TOPN`, `EXCLUDE_REGEX`, `WHITELIST_REGEX`)
- `scripts/reports/ctd_ddi_patient_overlay_html.sh`
- `scripts/reports/build_ctd_report_v2.sh`
- `scripts/reports/inject_expr_balance.sh`
- `scripts/reports/inject_ddi_overlay.sh`

**Environment to set**
```bash
source scripts/dev/gs_session.sh
use_patient 2                         # or your target upload_id
# Optional knobs for DDI:
export MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300
# Optional filters:
export EXCLUDE_REGEX=""               # disable default environment-exposure filter
export WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$'

Run flow

build_balance
build_ddi
report_v2
sanity


Outputs (default OUTDIR: reports/upload_2)

Balance: ctd_expr_balance_{genes,chemicals,kpis,sentinels}.csv, ctd_expr_balance_{body,html}.html

DDI: ctd_ddi_patient_overlay.csv, ctd_ddi_patient_overlay_{body,html}.html

Full: ctd_report_v2.html (+ optional ctd_report_v2.pdf)
