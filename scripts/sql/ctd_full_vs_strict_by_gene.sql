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
)
SELECT
  j.gene_symbol,
  j.action_family,
  j.n_full,
  j.n_strict,
  j.pruned,
  CASE
    WHEN j.n_full = 0 THEN 'no_data'
    WHEN (j.n_full - j.n_strict)::float / NULLIF(j.n_full,0) >= 0.25 THEN 'high_prune'
    ELSE 'ok'
  END AS prune_flag,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.v_ctd_enriched_strict_v2 v
      WHERE v.is_strict
        AND v.gene_symbol = j.gene_symbol
        AND v.action_family IN ('binds','modifies')
    ) THEN 'mechanistic_signal'
    ELSE 'none'
  END AS actionability_note
FROM joined j
WHERE j.pruned > 0
ORDER BY j.pruned DESC, j.gene_symbol, j.action_family;
