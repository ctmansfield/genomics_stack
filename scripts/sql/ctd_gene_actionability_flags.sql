-- ctd_gene_actionability_flags.sql
-- Summarize per-gene pruning + simple actionability hints for the report.

WITH cte_full AS (
  SELECT gene_symbol, public.ctd_action_family(action_norm) AS action_family, COUNT(*) AS n_full
  FROM public.gene_to_chemical
  GROUP BY 1,2
),
cte_strict AS (
  SELECT gene_symbol, action_family, COUNT(*) AS n_strict
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
  GROUP BY 1,2
),
joined AS (
  SELECT
    COALESCE(f.gene_symbol, s.gene_symbol) AS gene_symbol,
    COALESCE(f.action_family, s.action_family) AS action_family,
    COALESCE(f.n_full, 0)  AS n_full,
    COALESCE(s.n_strict, 0) AS n_strict,
    GREATEST(COALESCE(f.n_full,0)-COALESCE(s.n_strict,0),0) AS pruned
  FROM cte_full f
  FULL OUTER JOIN cte_strict s
    ON f.gene_symbol = s.gene_symbol AND f.action_family = s.action_family
),
by_gene AS (
  SELECT gene_symbol,
         SUM(n_full)   AS n_full,
         SUM(n_strict) AS n_strict,
         SUM(pruned)   AS pruned
  FROM joined
  GROUP BY 1
),
flags AS (
  SELECT
    g.gene_symbol,
    g.n_full,
    g.n_strict,
    g.pruned,
    CASE
      WHEN g.n_full = 0 THEN 'no_data'
      WHEN (g.n_full - g.n_strict)::float / NULLIF(g.n_full,0) >= COALESCE(NULLIF(current_setting('ctd.prune_threshold', true), '')::float, 0.25)
        THEN 'high_prune'
      ELSE 'ok'
    END AS prune_flag,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.v_ctd_enriched_strict_v2 v
        WHERE v.is_strict AND v.gene_symbol=g.gene_symbol AND v.action_family IN ('binds','modifies')
      ) THEN 'mechanistic_signal'
      ELSE 'none'
    END AS actionability_note
  FROM by_gene g
)
SELECT
  f.gene_symbol,
  f.n_full,
  f.n_strict,
  f.pruned,
  f.prune_flag,
  f.actionability_note,
  -- Short, actionable comment for the PDF
  CASE
    WHEN f.prune_flag='high_prune' AND f.actionability_note='mechanistic_signal'
      THEN 'Large non-specific CTD signal removed; keep binds/modifies edges for MOA leads.'
    WHEN f.prune_flag='high_prune'
      THEN 'Heavily pruned non-specific edges; consider limiting to activates/inhibits/binds.'
    WHEN f.prune_flag='no_data'
      THEN 'No CTD edges available; skip.'
    ELSE 'OK after pruning.'
  END AS comment
FROM flags f
ORDER BY f.pruned DESC, f.gene_symbol;
