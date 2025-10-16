\set bal_thr    :BAL_THR
\set min_genes  :MIN_GENES
\set min_total  :MIN_TOTAL
\set excl_rx    :'EXCLUDE_REGEX'

WITH patient_genes AS (
  SELECT gene_symbol FROM public.v_patient_genes_active  -- uses app.patient_upload_id
),
expr AS (
  SELECT
    gtc.gene_symbol,
    gtc.chem_id,
    (gtc.action_norm ~* '(^|\|)increases\^expression(\||$)')::int AS inc,
    (gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)')::int AS dec
  FROM public.v_ctd_enriched_strict_v2 gtc
  WHERE gtc.is_strict
    AND (gtc.action_norm ~* '(^|\|)increases\^expression(\||$)'
      OR gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)')
    AND gtc.gene_symbol IN (SELECT gene_symbol FROM patient_genes)
),
roll AS (
  SELECT
    e.chem_id,
    COUNT(DISTINCT e.gene_symbol) AS genes_covered,
    SUM(e.inc) AS inc_n,
    SUM(e.dec) AS dec_n,
    SUM(e.inc + e.dec) AS total_n
  FROM expr e
  GROUP BY e.chem_id
),
named AS (
  SELECT r.*, COALESCE(c.name, r.chem_id) AS drug_name
  FROM roll r
  LEFT JOIN public.chemicals c ON c.chem_id = r.chem_id
),
scored AS (
  SELECT n.*,
         CASE WHEN total_n>0 THEN inc_n::float/total_n ELSE 0 END AS inc_frac,
         CASE WHEN total_n>0 THEN dec_n::float/total_n ELSE 0 END AS dec_frac
  FROM named n
),
flags AS (
  SELECT s.*,
         CASE
           WHEN :excl_rx <> '' AND s.drug_name ~* :excl_rx THEN 'excluded_by_regex'
           WHEN s.total_n < :min_total THEN 'below_MIN_TOTAL'
           WHEN s.genes_covered < :min_genes THEN 'below_MIN_GENES'
           ELSE 'passes_filters'
         END AS primary_reason,
         (CASE WHEN :excl_rx <> '' AND s.drug_name ~* :excl_rx THEN 1 ELSE 0 END) AS r_excl,
         (CASE WHEN s.total_n < :min_total THEN 1 ELSE 0 END) AS r_tot,
         (CASE WHEN s.genes_covered < :min_genes THEN 1 ELSE 0 END) AS r_genes
  FROM scored s
)
SELECT
  chem_id,
  drug_name,
  genes_covered, inc_n, dec_n, total_n,
  round(inc_frac::numeric,3) AS inc_frac,
  round(dec_frac::numeric,3) AS dec_frac,
  primary_reason,
  (CASE WHEN r_excl=1 THEN 'name_regex ' ELSE '' END) ||
  (CASE WHEN r_tot=1  THEN 'min_total '  ELSE '' END) ||
  (CASE WHEN r_genes=1 THEN 'min_genes ' ELSE '' END) AS all_reasons
FROM flags
ORDER BY
  (primary_reason = 'passes_filters') DESC,
  total_n DESC,
  drug_name NULLS LAST;
