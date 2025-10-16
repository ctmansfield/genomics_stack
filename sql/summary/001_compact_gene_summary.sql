CREATE OR REPLACE VIEW public.v_gene_summary AS
WITH base AS (
  SELECT gene_symbol FROM public.gene_catalog
)
SELECT
  b.gene_symbol,
  COALESCE(go.n_go, 0)       AS n_go,
  COALESCE(go.n_bp, 0)       AS n_bp,
  COALESCE(go.n_mf, 0)       AS n_mf,
  COALESCE(go.n_cc, 0)       AS n_cc,
  COALESCE(pw.n_pathways, 0) AS n_pathways,
  COALESCE(pm.n_pubs, 0)     AS n_pubmed,   -- ← fixed: mv_pubmed_counts column is n_pubs
  COALESCE(dr.n_drugs, 0)    AS n_drugs,
  COALESCE(hp.n_hpo, 0)      AS n_hpo,
  (COALESCE(go.n_go,0)
   + COALESCE(pw.n_pathways,0)
   + COALESCE(pm.n_pubs,0)
   + COALESCE(dr.n_drugs,0)
   + COALESCE(hp.n_hpo,0))   AS n_total
FROM base b
LEFT JOIN public.mv_go_counts        go ON go.gene_symbol = b.gene_symbol
LEFT JOIN public.mv_pathway_counts   pw ON pw.gene_symbol = b.gene_symbol
LEFT JOIN public.mv_pubmed_counts    pm ON pm.gene_symbol = b.gene_symbol
LEFT JOIN public.mv_gene_drug_counts dr ON dr.gene_symbol = b.gene_symbol
LEFT JOIN public.mv_hpo_counts_v2       hp ON hp.gene_symbol = b.gene_symbol;
