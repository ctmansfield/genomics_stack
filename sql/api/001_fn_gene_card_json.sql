CREATE OR REPLACE FUNCTION public.gene_card_json(p_symbol text)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH s AS (
  SELECT * FROM public.v_gene_summary WHERE gene_symbol = p_symbol
),
h AS (
  SELECT hpo_id, hpo_label
  FROM public.v_gene_edges_hpo
  WHERE gene_symbol = p_symbol
  GROUP BY hpo_id, hpo_label
  ORDER BY COUNT(*) DESC, hpo_label
  LIMIT 5
),
d AS (
  SELECT drug_name, drug_concept_norm
  FROM public.v_gene_edges_drug
  WHERE gene_symbol = p_symbol
  GROUP BY drug_name, drug_concept_norm
  ORDER BY COUNT(*) DESC, drug_name
  LIMIT 5
),
p AS (
  SELECT p.pathway_id, p.label
  FROM public.gene_to_pathway e
  JOIN public.pathways p USING (pathway_id)
  WHERE e.gene_symbol = p_symbol
  GROUP BY p.pathway_id, p.label
  ORDER BY COUNT(*) DESC, p.label
  LIMIT 5
)
SELECT jsonb_build_object(
  'gene_symbol', s.gene_symbol,
  'counts', jsonb_build_object(
    'n_total', s.n_total, 'n_go', s.n_go, 'n_pathways', s.n_pathways,
    'n_pubmed', s.n_pubmed, 'n_drugs', s.n_drugs, 'n_hpo', s.n_hpo
  ),
  'top_hpo', COALESCE((SELECT jsonb_agg(jsonb_build_object('hpo_id', hpo_id, 'label', hpo_label)) FROM h), '[]'::jsonb),
  'top_drugs', COALESCE((SELECT jsonb_agg(jsonb_build_object('drug_name', drug_name, 'concept', drug_concept_norm)) FROM d), '[]'::jsonb),
  'top_pathways', COALESCE((SELECT jsonb_agg(jsonb_build_object('pathway_id', pathway_id, 'label', label)) FROM p), '[]'::jsonb)
)
FROM s
GROUP BY s.gene_symbol, s.n_total, s.n_go, s.n_pathways, s.n_pubmed, s.n_drugs, s.n_hpo;
$$;
