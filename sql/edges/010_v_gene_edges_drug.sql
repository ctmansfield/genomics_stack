-- Friendly Drug edges view for the app.
-- Aligns with your gene_to_drug schema (drug_name, drug_concept_id, it_norm, dc_norm present).
CREATE OR REPLACE VIEW public.v_gene_edges_drug AS
SELECT
  gene_symbol,
  drug_name,
  drug_concept_id,
  it_norm       AS interaction_type,   -- normalized interaction type
  dc_norm       AS drug_concept_norm,     -- normalized directionality
  source
FROM public.gene_to_drug;
