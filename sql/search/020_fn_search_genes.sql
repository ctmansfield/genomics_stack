-- sql/search/020_fn_search_genes.sql
CREATE OR REPLACE FUNCTION public.search_genes(q text, lim int DEFAULT 20)
RETURNS TABLE (
  gene_symbol text,
  rank        real,
  n_total     int,
  n_pubmed    int,
  n_go        int,
  n_pathways  int,
  n_drugs     int,
  n_hpo       int
) LANGUAGE plpgsql AS $$
DECLARE
  tsquery text;
  target  text;
BEGIN
  -- build prefix tsquery like: 'tp53:* & mut:*'
  tsquery := (
    SELECT string_agg(tok || ':*', ' & ')
    FROM (
      SELECT regexp_replace(lower(x), '\W+', '', 'g') AS tok
      FROM unnest(regexp_split_to_array(coalesce(q,''), '\s+')) AS x
      WHERE x <> ''
    ) s
  );
  IF tsquery IS NULL OR tsquery = '' THEN
    tsquery := ':*'; -- match all minimally; rank will be low
  END IF;

  -- prefer materialized view if present
  SELECT CASE
           WHEN EXISTS (SELECT 1 FROM information_schema.tables
                        WHERE table_schema='public' AND table_name='mv_gene_search')
           THEN 'mv' ELSE 'view'
         END
    INTO target;

  IF target = 'mv' THEN
    RETURN QUERY
    SELECT
      g.gene_symbol,
      ts_rank_cd(g.search_vector, to_tsquery('simple', tsquery)) AS rank,
      g.n_total, g.n_pubmed, g.n_go, g.n_pathways, g.n_drugs, g.n_hpo
    FROM public.mv_gene_search g
    WHERE g.search_vector @@ to_tsquery('simple', tsquery)
    ORDER BY rank DESC, g.n_total DESC
    LIMIT lim;
  ELSE
    RETURN QUERY
    SELECT
      g.gene_symbol,
      ts_rank_cd(g.search_vector, to_tsquery('simple', tsquery)) AS rank,
      g.n_total, g.n_pubmed, g.n_go, g.n_pathways, g.n_drugs, g.n_hpo
    FROM public.v_gene_search g
    WHERE g.search_vector @@ to_tsquery('simple', tsquery)
    ORDER BY rank DESC, g.n_total DESC
    LIMIT lim;
  END IF;
END$$;
