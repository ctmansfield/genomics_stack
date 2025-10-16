#!/usr/bin/env bash
# Refresh only mv_gene_search (if present). No env changes.

set +e
missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then echo "[ERROR] Missing required env: ${missing[*]}"; exit 1; fi

echo "[INFO] Refreshing mv_gene_search on ${PGHOST}:${PGPORT}/${PGDATABASE}"
psql -v ON_ERROR_STOP=1 <<'SQL'
-- If you later add a UNIQUE index (not required), you can do CONCURRENTLY.
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_gene_search;
SQL
ec=$?
[ $ec -eq 0 ] && echo "[OK] mv_gene_search refreshed." || echo "[ERROR] Refresh failed (exit $ec)."
exit $ec
