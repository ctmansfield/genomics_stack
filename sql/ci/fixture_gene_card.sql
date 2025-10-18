-- --- Minimal schema for CI smoke test ---
-- Fake summary + edges tables with just enough columns for gene_card_json()

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

CREATE TABLE public.v_gene_summary (
  gene_symbol text PRIMARY KEY,
  n_go bigint, n_bp bigint, n_mf bigint, n_cc bigint,
  n_pathways bigint, n_pubmed bigint, n_drugs bigint, n_hpo bigint,
  n_total bigint
);

CREATE TABLE public.v_gene_edges_hpo (
  gene_symbol text, hpo_id text, hpo_label text, evidence text, source text
);

CREATE TABLE public.v_gene_edges_drug (
  gene_symbol text, drug_name text, drug_concept_norm text
);

CREATE TABLE public.v_gene_edges_pathway (
  gene_symbol text, pathway_id text, pathway_label text, evidence text
);

INSERT INTO public.v_gene_summary
  (gene_symbol,n_go,n_bp,n_mf,n_cc,n_pathways,n_pubmed,n_drugs,n_hpo,n_total)
VALUES
  ('TP53',287,198,54,35,127,11608,458,223,12703);

INSERT INTO public.v_gene_edges_hpo VALUES
  ('TP53','HP:0002027','Abdominal pain',NULL,'HPO'),
  ('TP53','HP:0012743','Abdominal obesity',NULL,'HPO');

INSERT INTO public.v_gene_edges_drug VALUES
  ('TP53','EPRENETAPOPT','ncit:C85465'),
  ('TP53','SIREMADLIN','ncit:C116325');

INSERT INTO public.v_gene_edges_pathway VALUES
  ('TP53','R-HSA-109581','Apoptosis','TAS'),
  ('TP53','R-HSA-1257604','PIP3 activates AKT signaling','TAS');

-- Function (same shape as repo, simplified to read our CI tables)
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
px AS (
  SELECT pathway_id, pathway_label
  FROM public.v_gene_edges_pathway
  WHERE gene_symbol = p_symbol
  GROUP BY pathway_id, pathway_label
  ORDER BY COUNT(*) DESC, pathway_label
  LIMIT 5
)
SELECT jsonb_build_object(
  'gene_symbol', s.gene_symbol,
  'counts', jsonb_build_object(
    'n_total',    s.n_total,
    'n_go',       s.n_go,
    'n_pathways', s.n_pathways,
    'n_pubmed',   s.n_pubmed,
    'n_drugs',    s.n_drugs,
    'n_hpo',      s.n_hpo
  ),
  'top_hpo',       COALESCE((SELECT jsonb_agg(jsonb_build_object('hpo_id', hpo_id, 'label', hpo_label)) FROM h),  '[]'::jsonb),
  'top_drugs',     COALESCE((SELECT jsonb_agg(jsonb_build_object('drug_name', drug_name, 'concept', drug_concept_norm)) FROM d), '[]'::jsonb),
  'top_pathways',  COALESCE((SELECT jsonb_agg(jsonb_build_object('pathway_id', pathway_id, 'label', pathway_label)) FROM px), '[]'::jsonb)
)
FROM s;
$$;
