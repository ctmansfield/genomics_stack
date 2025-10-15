SELECT p.chem_id AS chem_id,
       c.name    AS chem_name,
       COUNT(*)  AS n_pruned
FROM public.v_ctd_edges_pruned_v2 p
LEFT JOIN public.chemicals c
  ON c.chem_id = p.chem_id
GROUP BY p.chem_id, c.name
ORDER BY n_pruned DESC
LIMIT 25;
