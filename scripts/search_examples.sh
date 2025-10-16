#!/usr/bin/env bash
# Demo queries for the gene search surface.
# - Respects your existing PG* env (PGHOST/PGPORT/PGUSER/PGDATABASE)
# - No strict mode, no env mutation.

set +e

missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")
if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"
  echo "       Activate your venv that exports PG* and re-run."
  exit 1
fi

echo "[INFO] Using ${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"
echo "[INFO] Will prefer mv_gene_search if present, else v_gene_search."

# Pretty psql settings (local to this session only)
PSQL_PREAMBLE=$(cat <<'SQL'
\pset format aligned
\pset pager off
\x auto
SQL
)

# Show what objects exist
psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'v_gene_search'  AS object, 'view' AS kind,
       (SELECT COUNT(*) FROM public.v_gene_search) AS rows;
SELECT 'mv_gene_search' AS object, 'matview' AS kind,
       (SELECT COUNT(*) FROM public.mv_gene_search) AS rows
  WHERE EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='mv_gene_search');
SQL

# Example 1: exact card via v_gene_summary (handy for UI detail view)
echo -e "\n[EXAMPLE] Exact card for TP53 from v_gene_summary"
psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT * FROM public.v_gene_summary WHERE gene_symbol='TP53';
SQL

# Example 2: prefix search via search_genes() helper (if installed)
echo -e "\n[EXAMPLE] Prefix search using search_genes('brca', 10)"
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='search_genes' AND pronamespace='public'::regnamespace) THEN
    -- function installed: use it
    RAISE NOTICE 'search_genes() present — running examples';
  ELSE
    RAISE NOTICE 'search_genes() not present — skipping function-based examples';
    RETURN;
  END IF;
END$$;

SELECT * FROM public.search_genes('brca', 10);
SELECT * FROM public.search_genes('vegf', 10);
SELECT * FROM public.search_genes('cftr abcc7', 10);
SQL

# Example 3: direct TSV query on the view (works even without the function)
echo -e "\n[EXAMPLE] View-based prefix search for 'brca*' (top 10)"
psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT gene_symbol, n_total
FROM public.v_gene_search
WHERE to_tsvector('simple','brca') @@ to_tsquery('simple','brca:*')
ORDER BY n_total DESC
LIMIT 10;
SQL

# Example 4: alias hit (CFTR via ABCC7) using the view
echo -e "\n[EXAMPLE] Alias hit: ABCC7 → CFTR"
psql -v ON_ERROR_STOP=1 <<'SQL'
SELECT gene_symbol, aliases
FROM public.v_gene_search
WHERE to_tsvector('simple', array_to_string(aliases,' ')) @@ to_tsquery('simple','abcc7:*')
LIMIT 5;
SQL

# Example 5: If MV exists, run a TSV query against it
echo -e "\n[EXAMPLE] MV-based search for 'tp5*' (if MV exists)"
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='mv_gene_search') THEN
    RAISE NOTICE 'mv_gene_search present — running query';
  ELSE
    RAISE NOTICE 'mv_gene_search not present — skipping MV example';
    RETURN;
  END IF;
END$$;

SELECT gene_symbol, n_total
FROM public.mv_gene_search
WHERE search_vector @@ to_tsquery('simple','tp5:*')
ORDER BY n_total DESC
LIMIT 10;
SQL

echo -e "\n[OK] Examples complete."
