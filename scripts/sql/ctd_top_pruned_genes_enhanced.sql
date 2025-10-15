WITH cte AS (
  SELECT * FROM (
    SELECT
      gene_symbol,
      SUM(CASE WHEN action_family <> 'other' THEN 1 ELSE 0 END) AS fams_non_other,
      SUM(1) FILTER (WHERE action_family = 'other') AS fams_other,
      SUM(n_full)   AS n_full_total,
      SUM(n_strict) AS n_strict_total,
      SUM(pruned)   AS pruned_total
    FROM (
      SELECT *
      FROM (
        -- reuse enhanced per-gene stats
        SELECT * FROM ( 
          WITH cte_full AS (
            SELECT gene_symbol, public.ctd_action_family(action_norm) AS action_family, COUNT(*) AS n_full
            FROM public.gene_to_chemical GROUP BY 1,2
          ),
          cte_strict AS (
            SELECT gene_symbol, action_family, COUNT(*) AS n_strict
            FROM public.v_ctd_enriched_strict_v2 WHERE is_strict GROUP BY 1,2
          )
          SELECT COALESCE(f.gene_symbol, s.gene_symbol) AS gene_symbol,
                 COALESCE(f.action_family, s.action_family) AS action_family,
                 COALESCE(f.n_full,0)  AS n_full,
                 COALESCE(s.n_strict,0) AS n_strict,
                 GREATEST(COALESCE(f.n_full,0)-COALESCE(s.n_strict,0),0) AS pruned
          FROM cte_full f
          FULL OUTER JOIN cte_strict s
            ON f.gene_symbol = s.gene_symbol AND f.action_family = s.action_family
        ) z
      ) j
    ) k
    GROUP BY gene_symbol
  ) agg
)
SELECT
  gene_symbol,
  n_full_total,
  n_strict_total,
  pruned_total,
  CASE WHEN n_full_total=0 THEN 0
       ELSE ROUND(100.0 * pruned_total / n_full_total, 1)
  END AS pruned_pct
FROM cte
WHERE n_full_total >= COALESCE(:min_full::int, 40)
  AND pruned_total   >= COALESCE(:min_pruned::int, 10)
  AND (COALESCE(:include_other::bool, false) OR fams_other = 0)
ORDER BY pruned_total DESC, pruned_pct DESC, gene_symbol
LIMIT COALESCE(:topn::int, 100);
