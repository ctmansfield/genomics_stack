-- HPO edges (v2 only) for app use.
CREATE OR REPLACE VIEW public.v_gene_edges_hpo_v2 AS
SELECT
  e.gene_symbol,
  e.hpo_id,
  t.label AS hpo_label,
  e.evidence,
  e.source
FROM public.gene_to_hpo_v2 e
JOIN public.hpo_terms t ON t.hpo_id = e.hpo_id;
