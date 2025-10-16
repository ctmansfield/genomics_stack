#!/usr/bin/env bash
# Verify compact summary artifacts. No env mutation, no strict mode.

set +e

missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"; exit 1
fi

echo "[INFO] Using PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"

psql -v ON_ERROR_STOP=1 <<'SQL'
-- counts
SELECT COUNT(*) AS n_genes FROM public.v_gene_summary;

-- top by total signal
SELECT gene_symbol, n_total, n_go, n_pathways, n_pubmed, n_drugs, n_hpo
FROM public.v_gene_summary
ORDER BY n_total DESC
LIMIT 20;

-- MV presence + size
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='mv_gene_summary'
  ) THEN
    RAISE NOTICE 'mv_gene_summary rows: %', (SELECT COUNT(*) FROM public.mv_gene_summary);
  ELSE
    RAISE NOTICE 'mv_gene_summary not present (view-only mode).';
  END IF;
END$$;
SQL
