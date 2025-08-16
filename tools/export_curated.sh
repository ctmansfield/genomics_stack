#!/usr/bin/env bash
set -euo pipefail
FILE_ID="${1:-3}"
PSQL(){ psql "host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics" -v ON_ERROR_STOP=1 "$@"; }
DATETIME="${DATETIME:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUTDIR="/mnt/nas_storage/outgoing/out.${DATETIME}"
install -d -m 0775 "$OUTDIR"
OUT="$OUTDIR/curated_report_${FILE_ID}.csv"
PSQL -c "\copy (
  SELECT file_id, sample_label, rsid, (allele1||'/'||allele2) AS genotype,
         category, impact_rank, evidence_level, risk_direction,
         layman_summary, medical_relevance,
         nutrition_support::text AS nutrition_support_json,
         citations, tags, updated_at
  FROM report_sample_curated
  WHERE file_id=${FILE_ID}
  ORDER BY COALESCE(impact_rank,9999), rsid
) TO '$OUT' CSV HEADER"
CAT="$OUTDIR/curated_catalog.csv"
PSQL -c "\copy (
  SELECT rsid, category::text, evidence::text, risk::text,
         impact_rank, layman_summary, medical_relevance,
         nutrition_support::text AS nutrition_support_json,
         citations, tags, updated_at
  FROM curated_rsid
  ORDER BY rsid
) TO '$CAT' CSV HEADER"
ln -sfn "$OUTDIR" /mnt/nas_storage/outgoing/latest
echo "[ok] wrote $OUT"
echo "[ok] wrote $CAT"
echo "[ok] latest -> $OUTDIR"
