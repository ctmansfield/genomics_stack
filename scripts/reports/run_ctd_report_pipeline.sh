#!/usr/bin/env bash
# CTD v2 pipeline: base report → DDI overlay → inject → PDFs.
# No strict mode. No 'exit'. No env sourcing. Assumes caller already activated any venv needed.

fail(){ echo "[run_ctd_report_pipeline] ERROR: $1" >&2; failed=1; }
note(){ echo "[run_ctd_report_pipeline] $1" >&2; }

# --- Paths (relative to repo root) ---
REPORTS_DIR="reports/upload_2"
BASE_BUILDER="scripts/reports/build_ctd_report_v2.sh"
INJECT_EXPR="scripts/reports/inject_expr_balance.sh"
INJECT_DDI="scripts/reports/inject_ddi_overlay.sh"
DDI_OVERLAY="scripts/reports/ctd_ddi_patient_overlay.sh"
DDI_PDF_HELPER="scripts/reports/ddi_overlay_pdf.sh"

# --- Tunables (safe defaults; can be overridden by caller env if desired) ---
: "${BAL_THR:=0.70}"
: "${MIN_TOTAL:=5}"
: "${MIN_GENES:=2}"
: "${TOPN:=300}"
: "${EXCLUDE_REGEX:=^(Reactive Oxygen Species|Oxygen|Plant Extracts|Lipopolysaccharides?|Particulate Matter|Lithocholic Acid|Chenodeoxycholic Acid|Glucose)$}"
: "${WHITELIST_REGEX:=^(Homocysteine|Ascorbic Acid|Estradiol)$}"

# Chromium (primary) + wkhtmltopdf (fallback) containers
: "${CHROME_IMG:=zenika/alpine-chrome:124}"
: "${CHROME_FLAGS:=--no-sandbox --headless=new --disable-gpu --disable-dev-shm-usage --no-first-run --disable-extensions --allow-file-access-from-files --user-data-dir=/tmp/chrome-profile}"
: "${WKHTML_IMG:=surnet/alpine-wkhtmltopdf:3.19-0.12.6-small}"

# --- Preflight (do not touch caller env; just check files/dirs) ---
failed=0
[ -x "$BASE_BUILDER" ] || fail "Missing or non-executable $BASE_BUILDER"
[ -x "$DDI_OVERLAY" ] || fail "Missing or non-executable $DDI_OVERLAY"
[ -x "$INJECT_EXPR" ] || fail "Missing or non-executable $INJECT_EXPR"
[ -x "$INJECT_DDI" ] || fail "Missing or non-executable $INJECT_DDI"

mkdir -p "$REPORTS_DIR" || fail "Cannot ensure output dir $REPORTS_DIR"
[ "${failed:-0}" -eq 0 ] || { echo "[run_ctd_report_pipeline] Preflight failed." >&2; return 1 2>/dev/null || exit 1; }

# --- 1) Build base CTD report (HTML) ---
note "Building base CTD v2 report..."
"$BASE_BUILDER" || fail "Base builder failed"

BASE_HTML="$REPORTS_DIR/ctd_report_v2.html"
[ -s "$BASE_HTML" ] || fail "Expected $BASE_HTML (non-empty)"
[ "${failed:-0}" -eq 0 ] || { echo "[run] Aborting after base build errors." >&2; return 1 2>/dev/null || exit 1; }

# --- 2) Generate DDI patient overlay (CSV/HTML) ---
note "Generating DDI overlay (strict expression-only edges; patient-scoped)..."
EXCLUDE_REGEX="$EXCLUDE_REGEX" WHITELIST_REGEX="$WHITELIST_REGEX" \
BAL_THR="$BAL_THR" MIN_TOTAL="$MIN_TOTAL" MIN_GENES="$MIN_GENES" TOPN="$TOPN" \
"$DDI_OVERLAY" || fail "DDI overlay generation failed"

DDI_HTML="$REPORTS_DIR/ctd_ddi_patient_overlay.html"
[ -s "$DDI_HTML" ] || fail "Expected overlay HTML $DDI_HTML"
[ "${failed:-0}" -eq 0 ] || { echo "[run] Aborting after overlay errors." >&2; return 1 2>/dev/null || exit 1; }

# --- 3) Inject sections (idempotent; injectors avoid duplicates) ---
note "Injecting Expression Balance section..."
"$INJECT_EXPR" || fail "Expression Balance injection failed"

note "Injecting DDI overlay section..."
"$INJECT_DDI" || fail "DDI overlay injection failed"
[ "${failed:-0}" -eq 0 ] || { echo "[run] Aborting after injection errors." >&2; return 1 2>/dev/null || exit 1; }

# --- 4) Render final PDF of main report ---
FINAL_HTML="$REPORTS_DIR/ctd_report_v2.html"
FINAL_PDF="$REPORTS_DIR/ctd_report_v2.pdf"

# Try Chrome (new headless)
note
