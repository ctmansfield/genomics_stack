#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Tunables (env overrides OK)
# ---------------------------
TOPN="${TOPN:-300}"
BAL_THR="${BAL_THR:-0.70}"
MIN_TOTAL="${MIN_TOTAL:-5}"
MIN_GENES="${MIN_GENES:-2}"
OUTDIR="${OUTDIR:-reports/upload_2}"
mkdir -p "$OUTDIR"

# Exclude obvious non-medication exposures by default.
# Set EXCLUDE_REGEX="" to disable.
EXCLUDE_REGEX="${EXCLUDE_REGEX:-^(Reactive Oxygen Species|Oxygen|Plant Extracts|Lipopolysaccharides|Particulate Matter|Glucose|Deoxycholic Acid|Glycocholic Acid|Taurocholic Acid)$}"

# Optional force-include by drug name (case-insensitive regex). Empty -> disabled.
# Example:
#   WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$'
WHITELIST_REGEX="${WHITELIST_REGEX:-}"

# -------------------------------------------------------
# Helpers: SQL predicates for exclude + whitelist
# -------------------------------------------------------
build_filter_clause() {
  if [[ -n "${EXCLUDE_REGEX}" ]]; then
    # SQL-escape single quotes
    local re_sql="${EXCLUDE_REGEX//\'/\'\'}"
    FILTER_CLAUSE="(drug_name IS NULL OR drug_name !~* '${re_sql}')"
  else
    FILTER_CLAUSE="TRUE"
  fi
}

build_wl_sql() {
  # WL_SQL expands to a SQL predicate or FALSE (never matches)
  if [[ -n "${WHITELIST_REGEX}" ]]; then
    local wl_sql="${WHITELIST_REGEX//\'/\'\'}"   # SQL-escape single quotes
    WL_SQL="drug_name ~* '${wl_sql}'"
  else
    WL_SQL="FALSE"
  fi
}

build_filter_clause
build_wl_sql

# -------------------------------------------------------
# Export: patient-specific CTD DDI overlay
# Requires: public.v_patient_genes_active
# (honors PGOPTIONS='-c app.patient_upload_id=…')
# -------------------------------------------------------
psql -v ON_ERROR_STOP=1 \
     -v min_total="$MIN_TOTAL" \
     -v min_genes="$MIN_GENES" \
     -v bal_thr="$BAL_THR" \
     -v topn="$TOPN" \
     -v filter_clause="$FILTER_CLAUSE" \
     -v wl_sql="$WL_SQL" \
     > "${OUTDIR}/ctd_ddi_patient_overlay.csv" <<'SQL'
COPY (
WITH expr AS (
  SELECT
    gtc.gene_symbol,
    gtc.chem_id,
    (gtc.action_norm ~* '(^|\|)increases\^expression(\||$)')::int AS inc,
    (gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)')::int AS dec
  FROM public.v_ctd_enriched_strict_v2 gtc
  WHERE gtc.is_strict
    AND (
      gtc.action_norm ~* '(^|\|)increases\^expression(\||$)'
      OR gtc.action_norm ~* '(^|\|)decreases\^expression(\||$)'
    )
    AND gtc.gene_symbol IN (SELECT gene_symbol FROM public.v_patient_genes_active)
),
roll AS (
  SELECT
    e.chem_id,
    COUNT(DISTINCT e.gene_symbol) AS genes_covered,
    SUM(e.inc)                    AS inc_n,
    SUM(e.dec)                    AS dec_n,
    SUM(e.inc + e.dec)            AS total_n,
    CASE WHEN SUM(e.inc + e.dec) > 0
         THEN SUM(e.inc)::float / SUM(e.inc + e.dec) ELSE 0 END AS inc_frac,
    CASE WHEN SUM(e.inc + e.dec) > 0
         THEN SUM(e.dec)::float / SUM(e.inc + e.dec) ELSE 0 END AS dec_frac
  FROM expr e
  GROUP BY e.chem_id
),
scored AS (
  SELECT
    r.chem_id,
    c.name AS drug_name,
    r.genes_covered, r.inc_n, r.dec_n, r.total_n, r.inc_frac, r.dec_frac,
    (r.total_n * (abs(r.inc_frac - 0.5)*2.0))::numeric(10,4) AS score,
    CASE
      WHEN r.inc_frac >= :bal_thr THEN 'inc_majority'
      WHEN r.dec_frac >= :bal_thr THEN 'dec_majority'
      ELSE 'balanced'
    END AS balance_flag
  FROM roll r
  LEFT JOIN public.chemicals c ON c.chem_id = r.chem_id
)
SELECT
  chem_id, drug_name, genes_covered, inc_n, dec_n, total_n,
  inc_frac, dec_frac, score, balance_flag,
  CASE
    WHEN (:wl_sql) THEN 'whitelist'
    WHEN (total_n >= :min_total AND genes_covered >= :min_genes) THEN 'meets_thresholds'
    ELSE 'filtered'
  END AS include_reason
FROM scored
WHERE (
        (total_n >= :min_total AND genes_covered >= :min_genes)
        OR (:wl_sql)
      )
  AND ( :filter_clause )
ORDER BY score DESC, total_n DESC, genes_covered DESC, drug_name NULLS LAST
LIMIT :topn
) TO STDOUT WITH CSV HEADER;
SQL
