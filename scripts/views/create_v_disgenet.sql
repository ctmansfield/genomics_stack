CREATE OR REPLACE VIEW public.v_disgenet AS
SELECT e.gene_symbol, e.disease_id, d.name AS disease_name, e.score, e.source, e.year, e.evidence
FROM public.disgenet_edges e
LEFT JOIN public.disgenet_diseases d USING (disease_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_disgenet_by_gene AS
SELECT gene_symbol, COUNT(*) n, max(score) max_score
FROM public.disgenet_edges GROUP BY 1;

CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_disgenet_by_gene ON public.mv_disgenet_by_gene(gene_symbol);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_disgenet_by_disease AS
SELECT disease_id, COUNT(*) n, max(score) max_score
FROM public.disgenet_edges GROUP BY 1;

CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_disgenet_by_disease ON public.mv_disgenet_by_disease(disease_id);
