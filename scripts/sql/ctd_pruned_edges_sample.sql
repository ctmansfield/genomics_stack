SELECT
  p.gene_symbol,
  p.chem_id,
  COALESCE(c.name, p.chem_id) AS chem_name,
  p.action_norm,
  p.action_family
FROM public.v_ctd_edges_pruned_v2 p
LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id
ORDER BY p.gene_symbol, p.chem_id
LIMIT 500;
