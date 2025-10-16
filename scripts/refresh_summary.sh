#!/usr/bin/env bash
# Refresh the compact per-gene summary MV only.
# Respects your existing PG* env; does not mutate env or use strict mode.

set +e

missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"; exit 1
fi

echo "[INFO] Refreshing mv_gene_summary on ${PGHOST}:${PGPORT}/${PGDATABASE}"

# If you created the UNIQUE index uq_mv_gene_summary_symbol, flip to CONCURRENTLY by uncommenting.
psql -v ON_ERROR_STOP=1 <<'SQL'
-- REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_gene_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_gene_summary;
SQL
ec=$?
[ $ec -eq 0 ] && echo "[OK] mv_gene_summary refreshed." || echo "[ERROR] Refresh failed (exit $ec)."
exit $ec
