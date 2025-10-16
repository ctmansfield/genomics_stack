#!/usr/bin/env bash
# Simple smoke checks. No env mutation; no strict mode.

set +e
fail=0
run() { psql -XAt -v ON_ERROR_STOP=1 -c "$1" || fail=1; }

echo "[INFO] Counts (non-zero expected)"
run "SELECT 'gene_to_go', COUNT(*) FROM public.gene_to_go;"
run "SELECT 'gene_to_pathway', COUNT(*) FROM public.gene_to_pathway;"
run "SELECT 'gene_to_pubmed', COUNT(*) FROM public.gene_to_pubmed;"
run "SELECT 'gene_to_drug', COUNT(*) FROM public.gene_to_drug;"
run "SELECT 'gene_to_hpo', COUNT(*) FROM public.gene_to_hpo;"
run "SELECT 'v_gene_summary', COUNT(*) FROM public.v_gene_summary;"

# basic thresholds (tune if you want)
echo "[INFO] Threshold sanity"
psql -XAt <<'SQL' || fail=1
WITH t AS (
  SELECT 'go' AS k, COUNT(*) AS n FROM public.gene_to_go UNION ALL
  SELECT 'pathway', COUNT(*) FROM public.gene_to_pathway UNION ALL
  SELECT 'pubmed', COUNT(*) FROM public.gene_to_pubmed UNION ALL
  SELECT 'drug', COUNT(*) FROM public.gene_to_drug UNION ALL
  SELECT 'hpo', COUNT(*) FROM public.gene_to_hpo
)
SELECT CASE WHEN MIN(n)>0 THEN 'OK' ELSE 'FAIL' END FROM t;
SQL

[ $fail -eq 0 ] && echo "[OK] Checks passed." || { echo "[ERROR] Some checks failed."; exit 1; }
