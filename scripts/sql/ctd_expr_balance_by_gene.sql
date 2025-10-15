WITH edges AS (
  SELECT
    gene_symbol,
    chem_id,
    action_norm,
    CASE WHEN action_norm ~* '(^|\\|)increases\\^expression(\\||$)' THEN 1 ELSE 0 END AS inc_expr,
    CASE WHEN action_norm ~* '(^|\\|)decreases\\^expression(\\||$)' THEN 1 ELSE 0 END AS dec_expr
  FROM public.gene_to_chemical
),
agg AS (
  SELECT
    gene_symbol,
    SUM(inc_expr) AS inc_expr,
    SUM(dec_expr) AS dec_expr
  FROM edges
  GROUP BY 1
)
SELECT
  a.gene_symbol,
  a.inc_expr,
  a.dec_expr,
  (a.inc_expr + a.dec_expr) AS total_expr,
  (a.inc_expr - a.dec_expr) AS net_expr,
  ROUND(100.0 * a.inc_expr / NULLIF(a.inc_expr + a.dec_expr,0), 1) AS inc_pct,
  ROUND(100.0 * a.dec_expr / NULLIF(a.inc_expr + a.dec_expr,0), 1) AS dec_pct,
  CASE
    WHEN (a.inc_expr + a.dec_expr) = 0 THEN 'none'
    WHEN GREATEST(a.inc_expr, a.dec_expr)::float / (a.inc_expr + a.dec_expr) >= 0.70 THEN 'skewed'
    ELSE 'balanced'
  END AS balance_flag,
  CASE
    WHEN (a.inc_expr + a.dec_expr) = 0 THEN 'No increase/decrease-of-expression edges.'
    WHEN a.inc_expr > a.dec_expr THEN
      'Net up-regulated: +'||(a.inc_expr - a.dec_expr)||' ('||ROUND(100.0 * a.inc_expr / NULLIF(a.inc_expr + a.dec_expr,0),1)||'%)'
    WHEN a.dec_expr > a.inc_expr THEN
      'Net down-regulated: -'||(a.dec_expr - a.inc_expr)||' ('||ROUND(100.0 * a.dec_expr / NULLIF(a.inc_expr + a.dec_expr,0),1)||'%)'
    ELSE 'Even split between increased and decreased expression.'
  END AS comment
FROM agg a
ORDER BY total_expr DESC, gene_symbol;
