#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'USAGE'
Usage:
  e2e_pipeline_check.sh --file-id <UUID-or-filename> [options]

Options:
  --dsn DSN                Postgres DSN (default: $PG_DSN or host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics)
  --import-table NAME      Import table/view (default: variants)
  --import-id-col NAME     Import file id column (default: file_id)
  --vep-table NAME         VEP annot table (default: vep_annotations)
  --vep-id-col NAME        VEP file id column (default: file_id)
  --report-dir DIR         Output directory for reports (default: risk_reports/out in repo)
  -h|--help                Show this help
USAGE
}

FILE_ID=""
DSN="${PG_DSN:-}"
IMPORT_TABLE="variants"
IMPORT_ID_COL="file_id"
VEP_TABLE="vep_annotations"
VEP_ID_COL="file_id"
REPORT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-id) FILE_ID="$2"; shift 2;;
    --dsn) DSN="$2"; shift 2;;
    --import-table) IMPORT_TABLE="$2"; shift 2;;
    --import-id-col) IMPORT_ID_COL="$2"; shift 2;;
    --vep-table) VEP_TABLE="$2"; shift 2;;
    --vep-id-col) VEP_ID_COL="$2"; shift 2;;
    --report-dir) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "${DSN}" ]]; then
  DSN="host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics"
fi

REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -n "${REPORT_DIR}" ]] || REPORT_DIR="${REPO_DIR}/risk_reports/out"
mkdir -p "${REPORT_DIR}"

psqlq() { PGPASSWORD='' psql "${DSN}" -Atqc "$1"; }

if [[ -z "${FILE_ID}" ]]; then echo "ERROR: --file-id is required"; exit 2; fi
if [[ ! "${FILE_ID}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  has_reg="$(psqlq "select to_regclass('public.ingest_registry') is not null")" || has_reg="f"
  if [[ "${has_reg}" == "t" ]]; then
    FILE_ID="$(psqlq "with x as (select file_id::text from ingest_registry where filename='${FILE_ID}' order by uploaded_at desc limit 1) select coalesce((select file_id from x),'')")"
    [[ -n "${FILE_ID}" ]] || { echo "Could not resolve file-id from filename"; exit 3; }
  fi
fi

echo "DSN: ${DSN}"
echo "File ID: ${FILE_ID}"
echo

imported="$(psqlq "select coalesce(count(*),0) from ${IMPORT_TABLE} where ${IMPORT_ID_COL}='${FILE_ID}'")" || imported=0
annotated="$(psqlq "select coalesce(count(*),0) from ${VEP_TABLE} where ${VEP_ID_COL}='${FILE_ID}'")" || annotated=0
status_row="$(psqlq "select coalesce(status,'') || '|' || coalesce(error,'') from ingest_registry where file_id='${FILE_ID}' limit 1" || true)"

echo "Import table:   ${IMPORT_TABLE}  records=${imported}"
echo "VEP table:      ${VEP_TABLE}     records=${annotated}"
if [[ -n "${status_row}" ]]; then
  status="${status_row%%|*}"; err="${status_row#*|}"
  echo "Registry:       status='${status}'"
  [[ -n "${err}" ]] && echo "Registry error: ${err}"
else
  echo "Registry:       (no row)"
fi

if [[ -x "${REPO_DIR}/scripts/reports/generate_full_report.py" ]]; then
  PG_DSN="${DSN}" REPORT_OUT="${REPORT_DIR}" python "${REPO_DIR}/scripts/reports/generate_full_report.py" --file-id "${FILE_ID}" || true
fi
if [[ -x "${REPO_DIR}/scripts/reports/generate_top10.py" ]]; then
  PG_DSN="${DSN}" REPORT_OUT="${REPORT_DIR}" python "${REPO_DIR}/scripts/reports/generate_top10.py" --file-id "${FILE_ID}" || true
fi

echo
echo "Report dir: ${REPORT_DIR}"
ls -1 "${REPORT_DIR}" 2>/dev/null || true
