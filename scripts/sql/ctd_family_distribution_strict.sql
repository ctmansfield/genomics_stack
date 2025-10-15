-- Counts by action family after STRICT pruning
SELECT action_family, COUNT(*) AS n_edges
FROM public.v_ctd_enriched_strict_v2
WHERE is_strict
GROUP BY 1
ORDER BY n_edges DESC;
