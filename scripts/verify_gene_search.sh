#!/usr/bin/env bash
# Verify search surface works. No env changes.

set +e
missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then echo "[ERROR] Missing required env: ${missing[*]}"; exit 1; fi

echo "[INFO] Using PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"

psql -v ON_ERROR_STOP=1 <<'SQL'
-- Row counts
SELECT 'v_gene_search' AS obj, COUNT(*) FROM public.v_gene_search
UNION ALL
SELECT 'mv_gene_search', COUNT(*) FROM information_schema.tables
 WHERE table_schema='public' AND table_name='mv_gene_search';

-- Example fuzzy searches (view)
SELECT gene_symbol, n_total
FROM public.v_gene_search
WHERE to_tsvector('simple', 'BRCA') @@ to_tsquery('simple','brca:*')
ORDER BY n_total DESC LIMIT 10;

-- Alias hit example (pick a known alias like ABCC7 for CFTR):
SELECT gene_symbol, aliases
FROM public.v_gene_search
WHERE to_tsvector('simple', array_to_string(aliases,' ')) @@ to_tsquery('simple','abcc7:*')
LIMIT 5;

-- If MV exists, do the same on MV
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='mv_gene_search') THEN
    RAISE NOTICE 'MV rows: %', (SELECT COUNT(*) FROM public.mv_gene_search);
    PERFORM 1 FROM public.mv_gene_search LIMIT 1;
  END IF;
END$$;
SQL
