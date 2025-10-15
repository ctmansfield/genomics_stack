SELECT
  p.gene_symbol,
  p.chem_id,
  COALESCE(c.name, split_part(p.chem_id,':',2)) AS chem_name,
  p.action_norm,
  p.action_family
FROM public.v_ctd_edges_pruned_v2 p
LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id
WHERE NOT (p.chem_id IN (
  'MESH:C005445',  -- triphenyl phosphate
  'MESH:D014635',  -- valproic acid
  'MESH:D014028'   -- tobacco smoke pollution
))
ORDER BY p.gene_symbol, p.chem_id
LIMIT COALESCE(:topn::int, 2000);
