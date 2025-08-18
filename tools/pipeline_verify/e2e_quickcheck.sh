#!/usr/bin/env bash
set -euo pipefail

# discover repo root once; fall back to /root/genomics-stack
REPO_DIR="${REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo /root/genomics-stack)}"

# defaults
IMPORT_TABLE="${IMPORT_TABLE:-variants}"
IMPORT_ID_COL="${IMPORT_ID_COL:-file_id}"
VEP_TABLE="${VEP_TABLE:-vep_annotations}"
VEP_ID_COL="${VEP_ID_COL:-file_id}"
REPORT_DIR="${REPORT_OUT:-$REPO_DIR/risk_reports/out}"
PG_DSN="${PG_DSN:-${1:-}}"

usage(){ echo "Usage: $0 --file-id ID [--dsn DSN] [--report-dir DIR]"; }
FILE_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-id) FILE_ID="$2"; shift 2;;
    --dsn) PG_DSN="$2"; shift 2;;
    --report-dir) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

[[ -n "$FILE_ID" ]] || { echo "Missing --file-id"; exit 2; }
[[ -n "${PG_DSN:-}" ]] || { echo "Missing DSN: export PG_DSN or pass --dsn"; exit 2; }

echo "[e2e] Using file-id: $FILE_ID"
mkdir -p "$REPORT_DIR"

# counts
IMP_CNT="$(psql "$PG_DSN" -Atqc "select count(*) from ${IMPORT_TABLE} where ${IMPORT_ID_COL}='${FILE_ID}';")"
VEP_CNT="$(psql "$PG_DSN" -Atqc "select count(*) from ${VEP_TABLE} where ${VEP_ID_COL}='${FILE_ID}';" || echo 0)"
echo "[e2e] Imported variants: $IMP_CNT"
echo "[e2e] VEP annotations : $VEP_CNT"

# reports (absolute paths!)
export REPORT_OUT="$REPORT_DIR"
export IMPORT_TABLE IMPORT_ID_COL VEP_TABLE VEP_ID_COL JOIN_KEY="${JOIN_KEY:-variant_id}"

python "$REPO_DIR/scripts/reports/generate_full_report.py" --file-id "$FILE_ID"
python "$REPO_DIR/scripts/reports/generate_top10.py"      --file-id "$FILE_ID"

echo "[e2e] Outputs:"
ls -1 "$REPORT_DIR" | sed 's/^/ - /'

# simple pass/fail
[[ "$IMP_CNT" -gt 0 ]] && echo "[e2e] PASS" || { echo "[e2e] FAIL: no imported rows"; exit 1; }
