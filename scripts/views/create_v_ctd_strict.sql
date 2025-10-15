-- strict overlay
CREATE OR REPLACE VIEW public.v_ctd_enriched_strict_v2 AS
SELECT
  gtc.gene_symbol,
  gtc.chem_id,
  gtc.action_norm,
  public.ctd_action_family(gtc.action_norm) AS action_family,
  CASE
    WHEN gtc.action_norm ~* '(^|\|)affects\^expression(\||$)'
      OR gtc.action_norm ~* '(^|\|)affects\^response to substance(\||$)'
      OR gtc.action_norm ~* '(\|)affects\^.+(\|)affects\^'
    THEN false ELSE true
  END AS is_strict
FROM public.gene_to_chemical gtc;

-- pruned sets
CREATE OR REPLACE VIEW public.v_ctd_edges_pruned_v2 AS
SELECT gtc.gene_symbol, gtc.chem_id, gtc.action_norm,
       public.ctd_action_family(gtc.action_norm) AS action_family
FROM public.v_ctd_enriched_strict_v2 gtc
WHERE NOT is_strict;

CREATE OR REPLACE VIEW public.v_ctd_edges_pruned_with_names AS
SELECT p.gene_symbol, p.chem_id, c.name AS chem_name, p.action_norm, p.action_family
FROM public.v_ctd_edges_pruned_v2 p
LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id;

-- rollups
DROP VIEW IF EXISTS public.v_ctd_pruned_by_gene;
CREATE VIEW public.v_ctd_pruned_by_gene AS
SELECT gene_symbol, COUNT(*) AS n_pruned
FROM public.v_ctd_edges_pruned_v2
GROUP BY 1
ORDER BY n_pruned DESC;

DROP VIEW IF EXISTS public.v_ctd_pruned_by_chemical;
CREATE VIEW public.v_ctd_pruned_by_chemical AS
SELECT chem_id, COUNT(*) AS n_pruned
FROM public.v_ctd_edges_pruned_v2
GROUP BY 1
ORDER BY n_pruned DESC;

-- strict rollups
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ctd_action_by_gene_strict AS
SELECT gene_symbol, action_family, COUNT(*) AS n_edges
FROM public.v_ctd_enriched_strict_v2
WHERE is_strict
GROUP BY 1,2;
CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_ctd_action_by_gene_strict
  ON public.mv_ctd_action_by_gene_strict(gene_symbol, action_family);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ctd_action_by_chemical_strict AS
SELECT chem_id, action_family, COUNT(*) AS n_edges
FROM public.v_ctd_enriched_strict_v2
WHERE is_strict
GROUP BY 1,2;
CREATE UNIQUE INDEX IF NOT EXISTS ix_mv_ctd_action_by_chemical_strict
  ON public.mv_ctd_action_by_chemical_strict(chem_id, action_family);
