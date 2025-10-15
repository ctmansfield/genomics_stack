WITH strict_signal AS (
  SELECT gene_symbol
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict AND action_family IN ('binds','modifies')
  GROUP BY gene_symbol
),
effect_summary AS (
  SELECT
    gene_symbol,
    SUM(CASE WHEN action_family='binds' THEN 1 ELSE 0 END) AS binds_edges,
    SUM(CASE WHEN action_family='modifies' THEN 1 ELSE 0 END) AS modifies_edges,
    SUM(CASE WHEN action_family='activates' THEN 1 ELSE 0 END) AS activates_edges,
    SUM(CASE WHEN action_family='inhibits' THEN 1 ELSE 0 END) AS inhibits_edges
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
  GROUP BY gene_symbol
)
SELECT
  e.gene_symbol,
  e.binds_edges,
  e.modifies_edges,
  e.activates_edges,
  e.inhibits_edges,
  (e.binds_edges + e.modifies_edges) AS mechanistic_edges
FROM effect_summary e
JOIN strict_signal s USING (gene_symbol)
WHERE (e.binds_edges + e.modifies_edges) >= COALESCE(:min_mech::int, 3)
ORDER BY mechanistic_edges DESC, e.gene_symbol
LIMIT COALESCE(:topn::int, 100);
