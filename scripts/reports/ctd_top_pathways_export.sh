#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-reports/upload_2}"
TOPN="${TOPN:-500}"
mkdir -p "$OUTDIR"

psql -v ON_ERROR_STOP=1 -c "\copy (
WITH strict_edges AS (
  SELECT DISTINCT gene_symbol, chem_id
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
),
gp AS (
  SELECT se.chem_id, gp.pathway_id, COUNT(DISTINCT se.gene_symbol) AS n_genes
  FROM strict_edges se
  JOIN public.gene_to_pathway gp ON gp.gene_symbol = se.gene_symbol
  GROUP BY 1,2
),
ranked AS (
  SELECT chem_id, pathway_id, n_genes,
         ROW_NUMBER() OVER (PARTITION BY chem_id ORDER BY n_genes DESC, pathway_id) AS rk
  FROM gp
),
top3 AS (
  SELECT r.chem_id,
         STRING_AGG( COALESCE(p.label, r.pathway_id) || ' ('|| r.n_genes ||')'
                   , '; ' ORDER BY r.rk ) AS top3
  FROM ranked r
  LEFT JOIN public.pathways p ON p.pathway_id=r.pathway_id
  WHERE r.rk <= 3
  GROUP BY r.chem_id
)
SELECT t.chem_id, COALESCE(c.name,t.chem_id) AS chem_name, t.top3
FROM top3 t
LEFT JOIN public.chemicals c ON c.chem_id=t.chem_id
ORDER BY chem_name
LIMIT ${TOPN}
) TO STDOUT WITH CSV HEADER" > "${OUTDIR}/ctd_top_pathways_per_chemical.csv"

echo "[ok] Wrote ${OUTDIR}/ctd_top_pathways_per_chemical.csv"
