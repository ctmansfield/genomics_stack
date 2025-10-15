\set ON_ERROR_STOP on
\echo [psql] building DDI overlay (TOPN=:topn) → :csv

\copy (
WITH adme AS (
  -- Fallback ADME/PK core genes. Replace with your patient view later.
  SELECT * FROM (VALUES
    ('CYP2D6'),('CYP3A4'),('CYP2C19'),('CYP2C9'),
    ('SLCO1B1'),('UGT1A1'),('VKORC1'),('DPYD'),
    ('TPMT'),('NAT2'),('CYP1A2'),('CYP2B6')
  ) AS t(gene_symbol)
),
edges AS (
  SELECT g.gene_symbol,
         g.chem_id,
         COALESCE(c.name, g.chem_id) AS drug_name,
         g.action_norm
  FROM public.v_ctd_enriched_strict_v2 g
  JOIN adme a ON a.gene_symbol = g.gene_symbol
  LEFT JOIN public.chemicals c ON c.chem_id = g.chem_id
),
marks AS (
  SELECT drug_name,
         COUNT(*) FILTER (WHERE action_norm ~* '(^|\\|)increases\\^expression(\\||$)') AS inc_n,
         COUNT(*) FILTER (WHERE action_norm ~* '(^|\\|)decreases\\^expression(\\||$)') AS dec_n,
         COUNT(*) FILTER (WHERE action_norm ~* '(^|\\|)affects\\^expression(\\||$)')   AS ambig_n,
         COUNT(*)                                                                      AS hits_n
  FROM edges
  GROUP BY drug_name
),
badges AS (
  SELECT
    drug_name,
    inc_n, dec_n, ambig_n, hits_n,
    CASE
      WHEN hits_n = 0 THEN 'none'
      WHEN inc_n::float/hits_n >= 0.70 THEN 'up'
      WHEN dec_n::float/hits_n >= 0.70 THEN 'down'
      ELSE 'mix'
    END AS badge
  FROM marks
)
SELECT
  COALESCE(drug_name,'(unknown)') AS drug_name,
  badge, inc_n, dec_n, ambig_n, hits_n
FROM badges
ORDER BY hits_n DESC, drug_name
LIMIT :topn
) TO :'csv' WITH CSV HEADER;
