WITH pruned AS (
  SELECT chem_id, COUNT(*) AS n_pruned
  FROM public.v_ctd_edges_pruned_v2
  GROUP BY 1
)
SELECT
  p.chem_id,
  COALESCE(c.name, split_part(p.chem_id, ':', 2)) AS chemical_name,
  p.n_pruned
FROM pruned p
LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id
WHERE p.n_pruned >= COALESCE(:min_pruned::int, 20)
ORDER BY p.n_pruned DESC, p.chem_id
LIMIT COALESCE(:topn::int, 100);
