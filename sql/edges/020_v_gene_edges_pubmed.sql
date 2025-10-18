-- Gene → PubMed edges (pmid only; enrich downstream as needed)
CREATE OR REPLACE VIEW public.v_gene_edges_pubmed AS
SELECT
  e.gene_symbol,
  e.pmid::bigint AS pmid
FROM public.gene_to_pubmed e;
