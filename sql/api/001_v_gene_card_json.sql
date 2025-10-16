-- Single-row JSON card per gene, composed from your summary + edges.
CREATE OR REPLACE VIEW public.v_gene_card_json AS
SELECT
  s.gene_symbol,
  jsonb_build_object(
    'symbol',     s.gene_symbol,
    'counts',     jsonb_build_object(
                     'go',        s.n_go,
                     'pathways',  s.n_pathways,
                     'pubmed',    s.n_pubmed,
                     'drugs',     s.n_drugs,
                     'hpo',       s.n_hpo,
                     'total',     s.n_total
                   ),
    'hpo_labels', COALESCE((
                     SELECT jsonb_agg(hpo_label ORDER BY cnt DESC, hpo_label)
                     FROM (
                       SELECT t.label AS hpo_label, COUNT(*) AS cnt
                       FROM public.gene_to_hpo_v2 e
                       JOIN public.hpo_terms t ON t.hpo_id = e.hpo_id
                       WHERE e.gene_symbol = s.gene_symbol
                       GROUP BY t.label
                       ORDER BY cnt DESC, t.label
                       LIMIT 8
                     ) q
                   ), '[]'::jsonb),
    'drugs',      COALESCE((
                     SELECT jsonb_agg(drug_name ORDER BY n DESC, drug_name)
                     FROM (
                       SELECT drug_name, COUNT(*) AS n
                       FROM public.gene_to_drug d
                       WHERE d.gene_symbol = s.gene_symbol
                       GROUP BY drug_name
                       ORDER BY n DESC, drug_name
                       LIMIT 12
                     ) x
                   ), '[]'::jsonb)
  ) AS card
FROM public.v_gene_summary s;
