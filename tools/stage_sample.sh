#!/usr/bin/env bash
set -euo pipefail

CSV="${1:-}"
FILE_ID="${2:-}"    # optional; if blank we will derive from filename
DB_DSN=${DB_DSN:-"host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics"}

if [[ -z "$CSV" || ! -f "$CSV" ]]; then
  echo "usage: $0 /abs/path/to/{full_report_X.csv|top10_X.csv} [FILE_ID]" >&2
  exit 1
fi

# Derive file_id from ..._123.csv if not provided
if [[ -z "${FILE_ID}" ]]; then
  b="$(basename "$CSV")"
  FILE_ID="$(sed -n 's/.*_\([0-9]\+\)\.csv/\1/p' <<<"$b")"
  FILE_ID="${FILE_ID:-0}"
fi

PSQL(){ psql "$DB_DSN" -v ON_ERROR_STOP=1 "$@"; }

# Header & column count
HDR="$(head -n1 "$CSV")"
NCOLS="$(awk -F',' 'NR==1{print NF}' "$CSV")"

# find index (1-based) of a header name, case-insensitive
idx_of () {
  awk -v t="$(tr '[:upper:]' '[:lower:]' <<<"$1")" -F',' '
    NR==1{
      for(i=1;i<=NF;i++){
        h=tolower($i); gsub(/"/,"",h);
        if(h==t){ print i; exit }
      }
    }' "$CSV"
}

RSID_IDX="$(idx_of rsid || true)"
A1_IDX="$(idx_of allele1 || true)"
A2_IDX="$(idx_of allele2 || true)"
SAMPLE_IDX="$(idx_of sample_label || true)"

if [[ -z "$RSID_IDX" ]]; then
  echo "CSV must include an 'rsid' column. Got header: $HDR" >&2
  exit 1
fi

# Build c1..cN column defs
COLS_DEF=""
for i in $(seq 1 "$NCOLS"); do
  COLS_DEF+="${COLS_DEF:+, }c${i} text"
done

# selectors (fallbacks if the column is missing)
[[ -n "$A1_IDX" ]] && A1SEL="COALESCE(NULLIF(c${A1_IDX},''),'NA')" || A1SEL="'NA'"
[[ -n "$A2_IDX" ]] && A2SEL="COALESCE(NULLIF(c${A2_IDX},''),'NA')" || A2SEL="'NA'"
[[ -n "$SAMPLE_IDX" ]] && SAMPLESEL="COALESCE(NULLIF(c${SAMPLE_IDX},''),'NA')" || SAMPLESEL="'NA'"

PSQL <<SQL
\\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS file_fdw;
DROP SERVER IF EXISTS csv_server CASCADE;
CREATE SERVER csv_server FOREIGN DATA WRAPPER file_fdw;

DROP FOREIGN TABLE IF EXISTS ft_generic;
CREATE FOREIGN TABLE ft_generic(
  ${COLS_DEF}
) SERVER csv_server
OPTIONS (filename :'csv_path', format 'csv', header 'true');

CREATE TABLE IF NOT EXISTS staging_array_calls (
  upload_id    int    NOT NULL,
  sample_label text   NOT NULL,
  rsid         text   NOT NULL,
  allele1      text   NOT NULL,
  allele2      text   NOT NULL
);

DELETE FROM staging_array_calls WHERE upload_id = ${FILE_ID};

INSERT INTO staging_array_calls (upload_id, sample_label, rsid, allele1, allele2)
SELECT ${FILE_ID}, ${SAMPLESEL}, c${RSID_IDX}, ${A1SEL}, ${A2SEL}
FROM ft_generic
WHERE c${RSID_IDX} IS NOT NULL AND c${RSID_IDX} <> '';

-- per-sample curated view (idempotent)
DROP VIEW IF EXISTS report_sample_curated;
CREATE VIEW report_sample_curated AS
SELECT
  s.upload_id                     AS file_id,
  s.sample_label,
  s.rsid,
  s.allele1, s.allele2,
  (s.allele1 || '/' || s.allele2) AS genotype,
  c.category::text                AS category,
  c.impact_rank,
  c.evidence::text                AS evidence_level,
  c.risk::text                    AS risk_direction,
  c.layman_summary,
  c.medical_relevance,
  c.nutrition_support,
  c.citations,
  c.tags,
  c.updated_at
FROM staging_array_calls s
JOIN curated_rsid c USING (rsid);

COMMIT;
SQL
