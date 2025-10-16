-- sql/search/030_v_gene_search_min.sql
CREATE OR REPLACE VIEW public.v_gene_search_min AS
SELECT
  gene_symbol,
  aliases[1:5]     AS aliases,     -- cap to 5 to keep payload small
  hpo_labels[1:5]  AS hpo_labels,  -- cap to 5
  n_total,
  n_pubmed,
  n_go,
  n_pathways,
  n_drugs,
  n_hpo
FROM public.v_gene_search;
