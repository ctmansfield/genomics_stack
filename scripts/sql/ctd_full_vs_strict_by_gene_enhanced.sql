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
)
SELECT
  COALESCE(f.gene_symbol, s.gene_symbol) AS gene_symbol,
  COALESCE(f.action_family, s.action_family) AS action_family,
  COALESCE(f.n_full,0)  AS n_full,
  COALESCE(s.n_strict,0) AS n_strict,
  GREATEST(COALESCE(f.n_full,0)-COALESCE(s.n_strict,0),0) AS pruned,
  CASE WHEN COALESCE(f.n_full,0) = 0 THEN 0
       ELSE ROUND(100.0 * (COALESCE(f.n_full,0)-COALESCE(s.n_strict,0)) / COALESCE(f.n_full,1), 1)
  END AS pruned_pct
FROM cte_full f
FULL OUTER JOIN cte_strict s
  ON f.gene_symbol = s.gene_symbol AND f.action_family = s.action_family
WHERE COALESCE(f.n_full,0) > 0
ORDER BY pruned DESC, pruned_pct DESC, gene_symbol, action_family;
