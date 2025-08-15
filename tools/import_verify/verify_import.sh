#!/usr/bin/env bash
set -euo pipefail
PGURL="${PGURL:?set PGURL}"
FILE="${1:?tsv path}"; TABLE="${2:-public.annotated_variants_staging}"
HAS_HEADER="${HAS_HEADER:-true}"
manifest="${FILE}.manifest.json"
[[ -f "$manifest" ]] || { echo "Missing manifest: $manifest"; exit 1; }
exp=$(jq -r '.expected_rows' "$manifest")
echo "[copy] Loading into $TABLE ..."
psql "$PGURL" -v ON_ERROR_STOP=1 -c "TRUNCATE ${TABLE};"
COPY_OUT=$(psql "$PGURL" -v ON_ERROR_STOP=1 -c "\copy ${TABLE} FROM '${FILE}' WITH (FORMAT csv, DELIMITER E'\t', HEADER ${HAS_HEADER}, QUOTE E'\b');" | grep -o 'COPY [0-9]\+' || true)
act=$(echo "$COPY_OUT" | awk '{print $2}')
[[ "$act" == "$exp" ]] || { echo "[FAIL] Row count mismatch: expected ${exp}, got ${act}"; exit 1; }
echo "[ok] Row count matches (${act})"
psql "$PGURL" -v ON_ERROR_STOP=1 <<'SQL'
WITH v AS (
  SELECT
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE chrom IS NULL OR chrom='') AS bad_chrom,
    COUNT(*) FILTER (WHERE pos   IS NULL)            AS bad_pos,
    COUNT(*) FILTER (WHERE ref   IS NULL OR ref='')  AS bad_ref,
    COUNT(*) FILTER (WHERE alt   IS NULL OR alt='')  AS bad_alt
  FROM public.annotated_variants_staging
)
SELECT CASE WHEN bad_chrom=0 AND bad_pos=0 AND bad_ref=0 AND bad_alt=0
  THEN '[OK] shape' ELSE '[FAIL] shape' END AS status, * FROM v;
SQL
