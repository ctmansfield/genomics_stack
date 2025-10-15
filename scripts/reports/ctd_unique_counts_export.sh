#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-reports/upload_2}"
mkdir -p "$OUTDIR"

psql -v ON_ERROR_STOP=1 -c "\copy (
WITH f AS (
  SELECT COUNT(*) AS edges, COUNT(DISTINCT gene_symbol || '|' || chem_id) AS pairs
  FROM public.gene_to_chemical
),
s AS (
  SELECT COUNT(*) AS edges, COUNT(DISTINCT gene_symbol || '|' || chem_id) AS pairs
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
)
SELECT
  f.edges  AS edges_full,
  s.edges  AS edges_strict,
  (f.edges - s.edges) AS edges_pruned,
  f.pairs  AS pairs_full,
  s.pairs  AS pairs_strict,
  (f.pairs - s.pairs) AS pairs_pruned
FROM f CROSS JOIN s
) TO STDOUT WITH CSV HEADER" > "${OUTDIR}/ctd_unique_counts.csv"

echo "[ok] Wrote ${OUTDIR}/ctd_unique_counts.csv"
