#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'USAGE'
Usage:
  e2e_pipeline_check.sh --file-id <UUID-or-filename> \
    [--dsn PG_DSN] \
    [--import-table TABLE --import-id-col COL] \
    [--vep-table TABLE --vep-id-col COL] \
    [--report-dir DIR]
USAGE
}
FILE_ID_OR_NAME=""; PG_DSN="${PG_DSN:-}"; IMPORT_TABLE="variants"; IMPORT_ID_COL="file_id"
VEP_TABLE="vep_annotations"; VEP_ID_COL="file_id"; REPORT_DIR="/root/genomics-stack/risk_reports/out"
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo /root/genomics-stack)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-id) FILE_ID_OR_NAME="$2"; shift 2;;
    --dsn) PG_DSN="$2"; shift 2;;
    --import-table) IMPORT_TABLE="$2"; shift 2;;
    --import-id-col) IMPORT_ID_COL="$2"; shift 2;;
    --vep-table) VEP_TABLE="$2"; shift 2;;
    --vep-id-col) VEP_ID_COL="$2"; shift 2;;
    --report-dir) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done
[[ -n "$FILE_ID_OR_NAME" ]] || { echo "ERROR: --file-id is required"; exit 2; }
if [[ -z "${PG_DSN:-}" ]] && [[ -f "$REPO_DIR/tools/env/load_env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$REPO_DIR/tools/env/load_env.sh" >/dev/null 2>&1 || true
fi
[[ -n "${PG_DSN:-}" ]] || { echo "ERROR: PG_DSN not set; export PG_DSN or pass --dsn"; exit 3; }
command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found (apt-get install -y postgresql-client)"; exit 4; }

HAS_REGISTRY=$(psql "$PG_DSN" -Atqc "SELECT to_regclass('public.ingest_registry') IS NOT NULL;" | tr -d '\r')
if [[ "$HAS_REGISTRY" == "t" ]]; then
  FILE_ID=$(psql "$PG_DSN" -Atqc "
    WITH x AS (
      SELECT file_id::text, filename, uploaded_at
      FROM ingest_registry
      WHERE file_id::text = '$FILE_ID_OR_NAME' OR filename = '$FILE_ID_OR_NAME'
      ORDER BY uploaded_at DESC LIMIT 1)
    SELECT COALESCE((SELECT file_id FROM x), '$FILE_ID_OR_NAME');" | tr -d '\r')
else
  FILE_ID="$FILE_ID_OR_NAME"
fi

IMPORTED=$(psql "$PG_DSN" -Atqc "SELECT COUNT(*) FROM ${IMPORT_TABLE} WHERE ${IMPORT_ID_COL}='${FILE_ID}';" | tr -d '\r' || echo "0")
VEP=$(psql "$PG_DSN" -Atqc "SELECT COUNT(*) FROM ${VEP_TABLE} WHERE ${VEP_ID_COL}='${FILE_ID}';" | tr -d '\r' || echo "0")

if [[ "$HAS_REGISTRY" == "t" ]]; then
  read -r FILENAME BYTE_SIZE MD5 TOTAL IMPORTED_REG ANNOTATED_REG STATUS REPORT_PATH < <(psql "$PG_DSN" -Atqc "
    SELECT COALESCE(filename,''), COALESCE(byte_size,0), COALESCE(md5,''),
           COALESCE(total_records,0), COALESCE(imported_records,0),
           COALESCE(annotated_records,0), COALESCE(status,''),
           COALESCE(report_path,'')
    FROM ingest_registry WHERE file_id='${FILE_ID}' LIMIT 1;" | tr -d '\r')
else
  FILENAME="$FILE_ID"; BYTE_SIZE=0; MD5=""; TOTAL=0; IMPORTED_REG=0; ANNOTATED_REG=0; STATUS=""; REPORT_PATH=""
fi

REPORT_FOUND=false; REPORT_HINT=""
if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
  REPORT_FOUND=true; REPORT_HINT="$REPORT_PATH"
elif ls "$REPORT_DIR"/*"$FILE_ID"* >/dev/null 2>&1; then
  REPORT_FOUND=true; REPORT_HINT="$(ls -1 "$REPORT_DIR"/*"$FILE_ID"* | head -n1)"
elif [[ -n "$FILENAME" ]] && ls "$REPORT_DIR"/*"$FILENAME"* >/dev/null 2>&1; then
  REPORT_FOUND=true; REPORT_HINT="$(ls -1 "$REPORT_DIR"/*"$FILENAME"* | head -n1)"
fi

PASS_IMPORT="FAIL"; PASS_VEP="FAIL"; PASS_REPORT="FAIL"
[[ "$IMPORTED" != "0" ]] && PASS_IMPORT="PASS"
[[ "$VEP" -ge "$IMPORTED" ]] && PASS_VEP="PASS"
$REPORT_FOUND && PASS_REPORT="PASS"

echo "=== E2E STATUS ==="
echo "File ID      : $FILE_ID"
echo "Filename     : $FILENAME"
echo "Imported     : $IMPORTED rows  [$PASS_IMPORT]"
echo "VEP rows     : $VEP rows       [$PASS_VEP]"
echo "Report       : $REPORT_FOUND   [$PASS_REPORT]  $REPORT_HINT"
echo "Registry     : status='$STATUS' total=$TOTAL imported_reg=$IMPORTED_REG annotated_reg=$ANNOTATED_REG"
echo "Import table : ${IMPORT_TABLE}.${IMPORT_ID_COL}"
echo "VEP table    : ${VEP_TABLE}.${VEP_ID_COL}"
echo "Report dir   : ${REPORT_DIR}"

OUT_DIR="$REPO_DIR/risk_reports/out"; mkdir -p "$OUT_DIR"
JSON="$OUT_DIR/e2e_status_${FILE_ID}.json"
cat > "$JSON" <<JSON
{
  "file_id": "${FILE_ID}",
  "filename": "${FILENAME}",
  "imported_rows": ${IMPORTED},
  "vep_rows": ${VEP},
  "report_found": ${REPORT_FOUND},
  "report_hint": "${REPORT_HINT}",
  "registry_status": "${STATUS}",
  "registry_total": ${TOTAL},
  "registry_imported": ${IMPORTED_REG},
  "registry_annotated": ${ANNOTATED_REG},
  "import_table": "${IMPORT_TABLE}",
  "import_id_col": "${IMPORT_ID_COL}",
  "vep_table": "${VEP_TABLE}",
  "vep_id_col": "${VEP_ID_COL}",
  "report_dir": "${REPORT_DIR}",
  "timestamp": "$(date -Iseconds)"
}
JSON
echo "Wrote: $JSON"

EXIT=0
[[ "$PASS_IMPORT" == "PASS" ]] || EXIT=1
[[ "$PASS_VEP" == "PASS" ]] || EXIT=1
[[ "$PASS_REPORT" == "PASS" ]] || EXIT=1
exit $EXIT
