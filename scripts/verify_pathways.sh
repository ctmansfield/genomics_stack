#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Counts"
psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'gene_to_pathway_v2' AS k, COUNT(*) FROM public.gene_to_pathway_v2;
SELECT 'pathways'          AS k, COUNT(*) FROM public.pathways;
SQL

echo "[INFO] TP53 (raw v2, joined w/ labels, view rows)"
psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'v2_raw',     COUNT(*) FROM public.gene_to_pathway_v2 WHERE gene_symbol='TP53';
SELECT 'v2_joined',  COUNT(*) FROM public.gene_to_pathway_v2 e JOIN public.pathways p USING(pathway_id) WHERE e.gene_symbol='TP53';
SELECT 'view_rows',  COUNT(*) FROM public.v_gene_edges_pathway WHERE gene_symbol='TP53';
SQL

echo "[INFO] Sample edges via VIEW"
psql -X -v ON_ERROR_STOP=1 -c \
"SELECT * FROM public.v_gene_edges_pathway WHERE gene_symbol='TP53' ORDER BY pathway_label LIMIT 10;"

echo "[INFO] Top genes by pathway edges (v2)"
psql -X -v ON_ERROR_STOP=1 -c \
"SELECT gene_symbol, COUNT(*) AS n FROM public.gene_to_pathway_v2 GROUP BY 1 ORDER BY n DESC LIMIT 10;"

echo "[OK] Pathway verification done."
