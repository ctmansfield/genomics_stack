-- CTD Action Taxonomy Enrichment (2025-10-13)
-- Creates mapping table, function, and (optionally) summary indexes/materialized views.
-- Safe to re-run.

BEGIN;

-- 1) Mapping table
CREATE TABLE IF NOT EXISTS public.ctd_action_map (
  action_norm   text PRIMARY KEY,
  action_family text NOT NULL CHECK (action_family IN ('activates','inhibits','binds','modifies','other'))
);

-- 2) Lookup function with heuristics fallback
CREATE OR REPLACE FUNCTION public.ctd_action_family(p_action_norm text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  fam text;
BEGIN
  IF p_action_norm IS NULL OR length(trim(p_action_norm)) = 0 THEN
    RETURN 'other';
  END IF;

  SELECT m.action_family INTO fam
  FROM public.ctd_action_map m
  WHERE m.action_norm = p_action_norm;

  IF fam IS NOT NULL THEN
    RETURN fam;
  END IF;

  -- Heuristic fallback (lowercased)
  -- Activates
  IF p_action_norm ~* '(increase|upregulat|activat|agonist|enhanc|positiv|stimulat|promot)' THEN
    RETURN 'activates';
  END IF;

  -- Inhibits
  IF p_action_norm ~* '(decrease|downregulat|inhibi|antagon|block|suppress|negativ|reduc)' THEN
    RETURN 'inhibits';
  END IF;

  -- Binds
  IF p_action_norm ~* '(bind|associat|interact|sequester|occup|affin|complex)' THEN
    RETURN 'binds';
  END IF;

  -- Modifies (PTMs & state changes)
  IF p_action_norm ~* '(phosphorylat|dephosphorylat|acetylat|deacetylat|ubiquitin|methylat|demethylat|oxidiz|reduc|cleav|proteolys|glycosylat|palmitoyl|sumoyl|translocat|localiz|fold|misfold|stabiliz|destabiliz|aggregate|edit|splice|process|modif)' THEN
    RETURN 'modifies';
  END IF;

  RETURN 'other';
END;
$$;

-- 3) Helpful index on gene_to_chemical.action_norm (if table accessible)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'ix_gene_to_chemical_action_norm'
  ) THEN
    BEGIN
      CREATE INDEX ix_gene_to_chemical_action_norm ON public.gene_to_chemical (action_norm);
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'Skipping index creation on gene_to_chemical(action_norm) due to privileges.';
      WHEN undefined_table THEN
        RAISE NOTICE 'Skipping index creation: gene_to_chemical not found.';
    END;
  END IF;
END $$;

COMMIT;
