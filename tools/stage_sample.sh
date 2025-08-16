#!/usr/bin/env bash
set -euo pipefail
CSV="${1:?Usage: stage_sample.sh /abs/path/to/full_report_X.csv [FILE_ID]}"
FILE_ID="${2:-$(basename "$CSV" | sed -n 's/.*_\([0-9]\+\)\.csv/\1/p')}"
FILE_ID="${FILE_ID:-0}"
PSQL(){ psql "host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics" -v ON_ERROR_STOP=1 "$@"; }

HDR="$(head -n1 "$CSV")"
get_idx(){ awk -v t="$(echo "$1" | tr '[:upper:]' '[:lower:]')" -F',' '
  NR==1{for(i=1;i<=NF;i++){h=tolower($i);gsub(/"/,"",h);if(h==t){print i; exit}}}' "$CSV"; }
RSID_IDX="$(get_idx rsid)"; A1_IDX="$(get_idx allele1)"; A2_IDX="$(get_idx allele2)"; SAMPLE_IDX="$(get_idx sample_label || true)"
[ -n "$RSID_IDX" ] || { echo "CSV missing 'rsid'. Header: $HDR"; exit 1; }
[ -n "$A1_IDX" ] || { echo "CSV missing 'allele1'. Header: $HDR"; exit 1; }
[ -n "$A2_IDX" ] || { echo "CSV missing 'allele2'. Header: $HDR"; exit 1; }

TMP="/tmp/stage_${FILE_ID}.$$.csv"
awk -F',' -v r="$RSID_IDX" -v a1="$A1_IDX" -v a2="$A2_IDX" -v s="${SAMPLE_IDX:-0}" '
  NR==1{next}
  {
    rsid=$r; a=$a1; b=$a2; sample=(s>0?$s:"NA");
    gsub(/^"|"$/, "", rsid); gsub(/^"|"$/, "", a); gsub(/^"|"$/, "", b); gsub(/^"|"$/, "", sample);
    print sample "," rsid "," a "," b
  }' "$CSV" > "$TMP"

PSQL <<SQL
\\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS staging_array_calls (
  upload_id    int    NOT NULL,
  sample_label text   NOT NULL,
  rsid         text   NOT NULL,
  allele1      text   NOT NULL,
  allele2      text   NOT NULL
);
CREATE TEMP TABLE _calls (sample_label text, rsid text, allele1 text, allele2 text);
\\copy _calls FROM PROGRAM 'cat "$TMP"' WITH (FORMAT csv)
DELETE FROM staging_array_calls WHERE upload_id = $FILE_ID;
INSERT INTO staging_array_calls (upload_id, sample_label, rsid, allele1, allele2)
SELECT $FILE_ID, sample_label, rsid, allele1, allele2 FROM _calls;
COMMIT;
SQL
echo "[ok] staged upload_id=$FILE_ID from $CSV ($(wc -l < "$TMP") rows)"
rm -f "$TMP"
