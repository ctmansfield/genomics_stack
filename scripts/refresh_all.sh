#!/usr/bin/env bash
# Refresh rollups, summary, and search surfaces in order.
# No env mutation; no strict mode.

set +e
missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then echo "[ERROR] Missing: ${missing[*]}"; exit 1; fi

echo "[INFO] Refreshing upstream rollups…"
psql -v ON_ERROR_STOP=1 <<'SQL'
REFRESH MATERIALIZED VIEW public.mv_go_counts;
REFRESH MATERIALIZED VIEW public.mv_pathway_counts;
REFRESH MATERIALIZED VIEW public.mv_pubmed_counts;
REFRESH MATERIALIZED VIEW public.mv_gene_drug_counts;
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_hpo_counts_v2;
-- If using v2 counts:
SQL || exit $?

echo "[INFO] Refreshing compact summary…"
./scripts/refresh_summary.sh || exit $?

echo "[INFO] Refreshing search MV (if present)…"
./scripts/refresh_gene_search.sh || exit $?

echo "[OK] All refreshed."
