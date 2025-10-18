-- Gene → Reactome (or pathway catalog) edges with labels
CREATE OR REPLACE VIEW public.v_gene_edges_pathway AS
SELECT
  e.gene_symbol,
  e.pathway_id,
  p.label        AS pathway_label,
  e.evidence
FROM public.gene_to_pathway e
JOIN public.pathways p USING (pathway_id);
