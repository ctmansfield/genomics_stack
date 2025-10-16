-- sql/api/010_fn_search_genes_json.sql
CREATE OR REPLACE FUNCTION public.search_genes_json(q text, lim int DEFAULT 15)
RETURNS jsonb LANGUAGE sql AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'gene_symbol', gene_symbol,
  'n_total',    n_total
) ORDER BY n_total DESC), '[]'::jsonb)
FROM public.search_genes(q, lim);
$$;
