#!/usr/bin/env bash
set +e
q="$*"; [ -z "$q" ] && { echo "usage: $0 query..."; exit 1; }
psql -X -v ON_ERROR_STOP=1 <<SQL
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='search_genes' AND pronamespace='public'::regnamespace
  ) THEN
    RAISE NOTICE 'search_genes() not installed — try view-based query:', now();
    RETURN;
  END IF;
END$$;
SQL
psql -X -v ON_ERROR_STOP=1 -c "SELECT * FROM public.search_genes('$q', 15);"
