#!/usr/bin/env bash
# Verifies presence + basic row counts + small samples for edges views.
set +e

echo "[INFO] Checking counts…"
psql -v ON_ERROR_STOP=1 <<'SQL'
\pset pager off
WITH t AS (
  SELECT 'v_gene_edges_hpo'     AS k, (SELECT COUNT(*) FROM public.v_gene_edges_hpo)     AS n UNION ALL
  SELECT 'v_gene_edges_drug'    AS k, (SELECT COUNT(*) FROM public.v_gene_edges_drug)    AS n UNION ALL
  SELECT 'v_gene_edges_pubmed'  AS k, (SELECT COUNT(*) FROM public.v_gene_edges_pubmed)  AS n UNION ALL
  SELECT 'v_gene_edges_pathway' AS k, (SELECT COUNT(*) FROM public.v_gene_edges_pathway) AS n UNION ALL
  SELECT 'v_gene_edges_go'      AS k, (SELECT COUNT(*) FROM public.v_gene_edges_go)      AS n
)
SELECT * FROM t ORDER BY k;

-- Samples
SELECT 'HPO' AS kind, * FROM public.v_gene_edges_hpo     WHERE gene_symbol='TP53' LIMIT 5;
SELECT 'Drug', * FROM public.v_gene_edges_drug           WHERE gene_symbol='TP53' LIMIT 5;
SELECT 'PMID', * FROM public.v_gene_edges_pubmed         WHERE gene_symbol='TP53' LIMIT 5;
SELECT 'Path', * FROM public.v_gene_edges_pathway        WHERE gene_symbol='TP53' LIMIT 5;
SELECT 'GO',   * FROM public.v_gene_edges_go             WHERE gene_symbol='TP53' LIMIT 5;
SQL
ec=$?
[ $ec -eq 0 ] && echo "[OK] edges look good." || echo "[ERROR] verify failed (exit $ec)."
exit $ec
