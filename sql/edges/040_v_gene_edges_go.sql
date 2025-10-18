-- Gene → GO term edges with labels
CREATE OR REPLACE VIEW public.v_gene_edges_go AS
SELECT
  e.gene_symbol,
  e.go_id,
  t.label    AS go_label,
  e.evidence
FROM public.gene_to_go e
JOIN public.go_terms t USING (go_id);
