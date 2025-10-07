#!/usr/bin/env bash
set -euo pipefail

# One-shot verification of ClinVar ingest acceptance criteria.
# Uses environment variables for DB connection:
#   PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
# Example (compose-mapped Postgres on localhost:5433):
#   PGHOST=127.0.0.1 PGPORT=5433 PGDATABASE=genomics PGUSER=postgres PGPASSWORD=... \
#     scripts/tests/verify_clinvar_ingest.sh

: "${PGHOST:=127.0.0.1}"
: "${PGPORT:=5432}"
: "${PGDATABASE:=genomics}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:?PGPASSWORD must be set}"

psql_args=(-X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE")

echo "[verify] Connecting to $PGUSER@$PGHOST:$PGPORT/$PGDATABASE"

echo
echo "1) Total clinvar_by_rsid rows (should be >= 1000)"
psql "${psql_args[@]}" -c "SELECT COUNT(*) AS total_rows FROM public.clinvar_by_rsid;"

echo
echo "1a) PASS/FAIL for threshold >= 1000"
psql "${psql_args[@]}" -c "SELECT CASE WHEN COUNT(*) >= 1000 THEN 'PASS' ELSE 'FAIL' END AS ingest_size, COUNT(*) AS total_rows FROM public.clinvar_by_rsid;"

echo
echo "2) Idempotency sanity: total vs distinct rsid (should be equal)"
psql "${psql_args[@]}" -c "SELECT COUNT(*) AS total_rows, COUNT(DISTINCT rsid) AS distinct_rsids, CASE WHEN COUNT(*) = COUNT(DISTINCT rsid) THEN 'PASS' ELSE 'FAIL' END AS idempotent_rowkey FROM public.clinvar_by_rsid;"

echo
echo "3) Review stars within 0..4 range (bad rows should be 0)"
psql "${psql_args[@]}" -c "SELECT COUNT(*) AS out_of_range FROM public.clinvar_by_rsid WHERE review_stars IS NOT NULL AND (review_stars < 0 OR review_stars > 4);"

echo
echo "4) Check rs1801133 and rs1800562 exist with non-null clnsig_raw and reasonable review_stars"
psql "${psql_args[@]}" -c "SELECT rsid, clnsig_raw, review_stars, last_eval_date FROM public.clinvar_by_rsid WHERE rsid IN ('rs1801133','rs1800562');"

echo
echo "5) Evidence check: v_evidence_counts present and has >0 evidence?"
# Detect whether the view exists
VIEW_OK=$(psql "${psql_args[@]}" -t -A -c "SELECT COALESCE(to_regclass('public.v_evidence_counts')::text,'')")
if [[ -z "$VIEW_OK" ]]; then
  echo "[verify] public.v_evidence_counts not found. Skipping evidence checks."
else
  # Check if evidence_count column exists
  HAS_COL=$(psql "${psql_args[@]}" -t -A -c "SELECT CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='v_evidence_counts' AND column_name='evidence_count'
    ) THEN 'yes' ELSE 'no' END")
  if [[ "$HAS_COL" == "yes" ]]; then
    psql "${psql_args[@]}" -c "SELECT EXISTS (SELECT 1 FROM public.v_evidence_counts WHERE evidence_count > 0) AS has_evidence;"
    echo
    echo "5a) Sample rows with evidence (up to 10)"
    psql "${psql_args[@]}" -c "SELECT * FROM public.v_evidence_counts WHERE evidence_count > 0 LIMIT 10;"
  else
    echo "[verify] Column evidence_count not found on v_evidence_counts; printing a sample to inspect column names."
    psql "${psql_args[@]}" -c "SELECT * FROM public.v_evidence_counts LIMIT 10;"
  fi
fi

echo
echo "[verify] Done."
