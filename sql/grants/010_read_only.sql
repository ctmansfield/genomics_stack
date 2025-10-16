-- sql/grants/010_read_only.sql
GRANT SELECT ON public.v_gene_summary, public.v_gene_search, public.v_gene_search_min,
                 public.v_gene_edges_hpo, public.v_gene_edges_drug
TO gene_readonly;

GRANT EXECUTE ON FUNCTION public.gene_card_json(text) TO gene_readonly;
