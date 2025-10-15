#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-reports/upload_2}"
TOPN="${TOPN:-200}"
mkdir -p "$OUTDIR"

# Export compounds that likely induce/inhibit key ADME genes (CYPs, ABCB1, SLCO1B1, UGTs)
psql -v ON_ERROR_STOP=1 -c "\copy (
WITH adme(gene_symbol) AS (
  VALUES
    ('CYP3A4'),('CYP3A5'),('CYP2D6'),('CYP2C9'),('CYP2C19'),('CYP1A2'),
    ('ABCB1'),('SLCO1B1'),('UGT1A1'),('UGT2B7')
),
expr AS (
  SELECT gtc.chem_id, gtc.gene_symbol,
         MAX( (gtc.action_norm ~* '(^|\\|)increases\\^expression(\\||$)')::int ) AS inc_expr,
         MAX( (gtc.action_norm ~* '(^|\\|)decreases\\^expression(\\||$)')::int ) AS dec_expr
  FROM public.gene_to_chemical gtc
  JOIN adme a USING(gene_symbol)
  GROUP BY 1,2
),
act AS (
  SELECT v.chem_id, v.gene_symbol,
         MAX( (v.action_family='activates')::int ) AS activates,
         MAX( (v.action_family='inhibits')::int ) AS inhibits
  FROM public.v_ctd_enriched_strict_v2 v
  JOIN adme a USING(gene_symbol)
  WHERE v.is_strict
  GROUP BY 1,2
),
merged AS (
  SELECT COALESCE(e.chem_id,a.chem_id) AS chem_id,
         COALESCE(e.gene_symbol,a.gene_symbol) AS gene_symbol,
         COALESCE(e.inc_expr,0) AS inc_expr,
         COALESCE(e.dec_expr,0) AS dec_expr,
         COALESCE(a.activates,0) AS activates,
         COALESCE(a.inhibits,0) AS inhibits
  FROM expr e FULL JOIN act a USING (chem_id,gene_symbol)
),
agg AS (
  SELECT m.chem_id,
         SUM( (m.inc_expr=1 OR m.activates=1)::int ) AS induces_n,
         SUM( (m.dec_expr=1 OR m.inhibits=1)::int ) AS inhibits_n,
         STRING_AGG(DISTINCT CASE WHEN (m.inc_expr=1 OR m.activates=1) THEN m.gene_symbol END, '|' )
           FILTER (WHERE (m.inc_expr=1 OR m.activates=1)) AS induces_genes,
         STRING_AGG(DISTINCT CASE WHEN (m.dec_expr=1 OR m.inhibits=1) THEN m.gene_symbol END, '|' )
           FILTER (WHERE (m.dec_expr=1 OR m.inhibits=1)) AS inhibits_genes
  FROM merged m
  GROUP BY 1
)
SELECT
  a.chem_id,
  COALESCE(c.name, a.chem_id) AS chem_name,
  induces_n,
  inhibits_n,
  COALESCE(induces_genes,'') AS induces_genes,
  COALESCE(inhibits_genes,'') AS inhibits_genes,
  CASE
    WHEN induces_n>0 AND inhibits_n=0 THEN 'Check DDI: ↑'
    WHEN inhibits_n>0 AND induces_n=0 THEN 'Check DDI: ↓'
    WHEN induces_n>0 AND inhibits_n>0 THEN 'Check DDI: mixed'
    ELSE 'no-DDI-flag'
  END AS badge
FROM agg a
LEFT JOIN public.chemicals c ON c.chem_id=a.chem_id
ORDER BY GREATEST(induces_n,inhibits_n) DESC, chem_name
LIMIT ${TOPN}
) TO STDOUT WITH CSV HEADER" > "${OUTDIR}/ctd_ddi_badges.csv"

echo "[ok] Wrote ${OUTDIR}/ctd_ddi_badges.csv"
