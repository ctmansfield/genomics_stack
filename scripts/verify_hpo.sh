#!/usr/bin/env bash
set +e

missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"
  exit 1
fi

echo "[INFO] Using PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"

psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'gene_to_hpo' AS table, COUNT(*) AS n FROM public.gene_to_hpo
UNION ALL
SELECT 'hpo_terms', COUNT(*) FROM public.hpo_terms
UNION ALL
SELECT 'mv_hpo_counts', COUNT(*) FROM public.mv_hpo_counts;

SELECT gene_symbol, COUNT(*) AS n
FROM public.gene_to_hpo
GROUP BY 1 ORDER BY n DESC
LIMIT 15;

SELECT COUNT(*) AS terms_without_edges
FROM public.hpo_terms t
LEFT JOIN public.gene_to_hpo e USING (hpo_id)
WHERE e.hpo_id IS NULL;

SELECT COUNT(*) AS bad_edges
FROM public.gene_to_hpo e
LEFT JOIN public.hpo_terms t USING (hpo_id)
WHERE t.hpo_id IS NULL;

TABLE public.gene_to_hpo LIMIT 10;
SQL
