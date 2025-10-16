\set ON_ERROR_STOP on
-- temp holder for patient genes
DROP TABLE IF EXISTS tmp_patient_adme;
CREATE TEMP TABLE tmp_patient_adme(gene_symbol text PRIMARY KEY);

INSERT INTO tmp_patient_adme(gene_symbol)
SELECT gene_symbol FROM public.v_patient_adme_genes;

-- Core overlay logic:
-- 1) Work only with strict CTD edges and expression directions
WITH expr AS (
  SELECT
    gtc.gene_symbol,
    gtc.chem_id,
    CASE
      WHEN gtc.action_norm ~* '(^|\|)increases\^expression(\||$)' THEN 1 ELSE 0
    END AS inc,
    CASE
      WHEN gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)' THEN 1 ELSE 0
    END AS dec
  FROM public.v_ctd_enriched_strict_v2 gtc
  WHERE gtc.is_strict
    AND (
      gtc.action_norm ~* '(^|\|)increases\^expression(\||$)'
      OR gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)'
    )
),
patient_hits AS (
  SELECT e.*
  FROM expr e
  JOIN tmp_patient_adme p
    ON p.gene_symbol = e.gene_symbol
),
drug_rollup AS (
  SELECT
    ph.chem_id,
    SUM(ph.inc) AS inc_n,
    SUM(ph.dec) AS dec_n,
    SUM(ph.inc + ph.dec) AS total_n
  FROM patient_hits ph
  GROUP BY ph.chem_id
),
badge AS (
  SELECT
    dr.chem_id,
    dr.inc_n,
    dr.dec_n,
    dr.total_n,
    CASE
      WHEN dr.total_n > 0 AND (dr.inc_n::float / dr.total_n) >= :BAL_THR THEN 'UP'
      WHEN dr.total_n > 0 AND (dr.dec_n::float / dr.total_n) >= :BAL_THR THEN 'DOWN'
      WHEN dr.total_n = 0 THEN 'NONE'
      ELSE 'MIX'
    END AS badge
  FROM drug_rollup dr
),
with_names AS (
  SELECT
    b.badge,
    c.name AS drug_name,
    b.inc_n,
    b.dec_n,
    b.total_n,
    b.chem_id
  FROM badge b
  LEFT JOIN public.chemicals c ON c.chem_id = b.chem_id
)
\copy (
  SELECT *
  FROM with_names
  ORDER BY (CASE badge WHEN 'UP' THEN 1 WHEN 'DOWN' THEN 2 WHEN 'MIX' THEN 3 ELSE 4 END),
           total_n DESC,
           COALESCE(drug_name, chem_id)
  LIMIT :TOPN
) TO :'OUTCSV' WITH CSV HEADER
