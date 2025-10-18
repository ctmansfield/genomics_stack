#!/usr/bin/env bash
# Genomics Stack session helpers
# Usage:
#   source scripts/dev/gs_session.sh
#   use_patient 2
#   build_balance
#   build_ddi             # or: WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$' build_ddi
#   report_v2             # rebuild + inject sections + (optional) render

set -euo pipefail

# --- Postgres env (edit PGPASSWORD) ---
export PGHOST=${PGHOST:-localhost}
export PGPORT=${PGPORT:-5432}
export PGUSER=${PGUSER:-genouser}
export PGDATABASE=${PGDATABASE:-genome_db}
export PGPASSWORD=${PGPASSWORD:-<PUT_YOUR_DB_PASSWORD_HERE>}   # <-- fill this once per machine

# Output dir used throughout reports
export OUTDIR=${OUTDIR:-reports/upload_2}

# Chrome-in-Docker renderer (same image you've been using)
render_pdf() {
  local html="$1"
  local pdf="${2:-${html%.html}.pdf}"
  docker run --rm -v "$PWD/$OUTDIR":/data zenika/alpine-chrome:124 \
    --no-sandbox --headless --disable-gpu \
    --print-to-pdf="/data/$(basename "$pdf")" "file:///data/$(basename "$html")"
}

# Pick the patient upload id (propagates to SQL via custom GUC)
use_patient() {
  local upload_id="$1"
  export PGOPTIONS="-c app.patient_upload_id=${upload_id}"
  echo "[ctx] PGOPTIONS=${PGOPTIONS}"
}

# ---------- Expression Balance ----------
# Exports CSVs + builds HTML body
build_balance() {
  echo "[run] Expression Balance: exports"
  scripts/reports/ctd_expr_balance_export.sh
  echo "[run] Expression Balance: HTML"
  scripts/reports/ctd_expr_balance_html.sh
}

# ---------- DDI Patient Overlay ----------
# Knobs (can override at call time): MIN_TOTAL, MIN_GENES, BAL_THR, TOPN, EXCLUDE_REGEX, WHITELIST_REGEX
build_ddi() {
  : "${MIN_TOTAL:=5}" : "${MIN_GENES:=2}" : "${BAL_THR:=0.70}" : "${TOPN:=300}"
  echo "[run] DDI overlay CSV (MIN_TOTAL=${MIN_TOTAL} MIN_GENES=${MIN_GENES} BAL_THR=${BAL_THR} TOPN=${TOPN})"
  MIN_TOTAL="$MIN_TOTAL" MIN_GENES="$MIN_GENES" BAL_THR="$BAL_THR" TOPN="$TOPN" \
  EXCLUDE_REGEX="${EXCLUDE_REGEX-}" WHITELIST_REGEX="${WHITELIST_REGEX-}" \
    scripts/reports/ctd_ddi_patient_overlay.sh

  echo "[run] DDI overlay HTML"
  scripts/reports/ctd_ddi_patient_overlay_html.sh
}

# ---------- Main Report (v2) ----------
# Rebuilds base HTML, injects Expression Balance + DDI overlay, optionally renders PDF
report_v2() {
  echo "[run] build_ctd_report_v2.sh"
  scripts/reports/build_ctd_report_v2.sh

  echo "[run] inject Expression Balance"
  scripts/reports/inject_expr_balance.sh

  echo "[run] inject DDI overlay"
  scripts/reports/inject_ddi_overlay.sh

  if [[ "${RENDER:-1}" -eq 1 ]]; then
    echo "[render] ${OUTDIR}/ctd_report_v2.html → PDF"
    render_pdf "${OUTDIR}/ctd_report_v2.html" "${OUTDIR}/ctd_report_v2.pdf"
  fi
}

# ---------- Quick sanity checks ----------
sanity() {
  echo "[ls] ${OUTDIR}"
  ls -lh "${OUTDIR}"/ctd_expr_balance_*.csv "${OUTDIR}/ctd_ddi_patient_overlay.csv" 2>/dev/null || true
  echo; echo "[peek] balance body & overlay body present?"
  [[ -f "${OUTDIR}/ctd_expr_balance_body.html" ]] && echo "✓ expr balance body"
  [[ -f "${OUTDIR}/ctd_ddi_patient_overlay_body.html" ]] && echo "✓ ddi overlay body"
  echo; echo "[grep] report embeds (expect exactly one each)"
  grep -n "Expression Balance embed" "${OUTDIR}/ctd_report_v2.html" || true
  grep -n "DDI overlay"              "${OUTDIR}/ctd_report_v2.html" || true
}

echo "[loaded] scripts/dev/gs_session.sh"
echo "  • Set PGPASSWORD inside this file (once) or export it before sourcing."
echo "  • Call: use_patient 2   # or your upload_id"
echo "  • Then: build_balance ; build_ddi ; report_v2 ; sanity"
