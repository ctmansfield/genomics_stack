#!/usr/bin/env bash
# Refresh upstream rollups in recommended order, then the compact summary MV.
# No env mutation; no strict mode. Flip CONCURRENTLY lines if unique indexes exist.

set +e

missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"; exit 1
fi

echo "[INFO] Refreshing rollups on ${PGHOST}:${PGPORT}/${PGDATABASE}"

psql -v ON_ERROR_STOP=1 <<'SQL'
REFRESH MATERIALIZED VIEW public.mv_go_counts;
REFRESH MATERIALIZED VIEW public.mv_pathway_counts;
REFRESH MATERIALIZED VIEW public.mv_pubmed_counts;
REFRESH MATERIALIZED VIEW public.mv_gene_drug_counts;
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_hpo_counts_v2;

-- If you installed a UNIQUE index on mv_gene_summary, flip to CONCURRENTLY:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_gene_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_gene_summary;
SQL
ec=$?
[ $ec -eq 0 ] && echo "[OK] Rollups + summary refreshed." || echo "[ERROR] Refresh failed (exit $ec)."
exit $ec
