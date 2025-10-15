-- View: v_gene_to_chemical_enriched
-- Minimal, schema-agnostic overlay using only guaranteed columns.

CREATE OR REPLACE VIEW public.v_gene_to_chemical_enriched AS
SELECT
  gtc.gene_symbol,
  gtc.chem_id,
  gtc.action_norm,
  public.ctd_action_family(gtc.action_norm) AS action_family
FROM public.gene_to_chemical gtc;

-- Optional materialized rollups for speed
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ctd_action_counts AS
SELECT action_family, count(*) AS n_edges
FROM public.v_gene_to_chemical_enriched
GROUP BY 1;

CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_ctd_action_counts_family
  ON public.mv_ctd_action_counts(action_family);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ctd_action_by_gene AS
SELECT gene_symbol, action_family, count(*) AS n_edges
FROM public.v_gene_to_chemical_enriched
GROUP BY 1,2;

CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_ctd_action_by_gene
  ON public.mv_ctd_action_by_gene(gene_symbol, action_family);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ctd_action_by_chemical AS
SELECT chem_id, action_family, count(*) AS n_edges
FROM public.v_gene_to_chemical_enriched
GROUP BY 1,2;

CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_ctd_action_by_chemical
  ON public.mv_ctd_action_by_chemical(chem_id, action_family);
