#!/usr/bin/env bash
set -Eeuo pipefail

PSQL=${PSQL:-psql -v ON_ERROR_STOP=1}
OUTDIR="${OUTDIR:-reports/upload_2}"
TOPN="${TOPN:-100}"                # number of rows for the CSVs (unused for KPIs)
BAL_THR="${BAL_THR:-0.70}"         # majority threshold (0.70 = 70%)

mkdir -p "$OUTDIR"

# === KPI row (used by HTML) ===
$PSQL -c "\copy (
  WITH base AS (
    SELECT gtc.gene_symbol,
           SUM( (gtc.action_norm ~* '(^|\\|)increases\\^expression(\\||$)')::int ) AS inc,
           SUM( (gtc.action_norm ~* '(^|\\|)decreases\\^expression(\\||$)')::int ) AS dec
    FROM public.gene_to_chemical gtc
    GROUP BY 1
  ),
  agg AS (
    SELECT gene_symbol,
           inc, dec,
           (inc+dec) AS total_expr,
           CASE WHEN (inc+dec)>0 THEN inc::float/(inc+dec) ELSE 0 END AS inc_frac,
           CASE WHEN (inc+dec)>0 THEN dec::float/(inc+dec) ELSE 0 END AS dec_frac
    FROM base
  )
  SELECT
    SUM( (inc_frac >= ${BAL_THR} AND total_expr > 0)::int ) AS inc_majority,
    SUM( (dec_frac >= ${BAL_THR} AND total_expr > 0)::int ) AS dec_majority,
    SUM( (inc_frac <  ${BAL_THR} AND dec_frac <  ${BAL_THR} AND total_expr > 0)::int ) AS balanced,
    SUM( (total_expr = 0)::int ) AS none
  FROM agg
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_expr_balance_kpis.csv"

# === Top genes by expression-edge volume ===
$PSQL -c "\copy (
  WITH base AS (
    SELECT gtc.gene_symbol,
           SUM( (gtc.action_norm ~* '(^|\\|)increases\\^expression(\\||$)')::int ) AS inc,
           SUM( (gtc.action_norm ~* '(^|\\|)decreases\\^expression(\\||$)')::int ) AS dec
    FROM public.gene_to_chemical gtc
    GROUP BY 1
  ),
  agg AS (
    SELECT gene_symbol,
           inc, dec,
           (inc+dec) AS total_expr,
           CASE WHEN (inc+dec)>0 THEN inc::float/(inc+dec) ELSE 0 END AS inc_frac,
           CASE WHEN (inc+dec)>0 THEN dec::float/(inc+dec) ELSE 0 END AS dec_frac,
           CASE
             WHEN (inc+dec)=0 THEN 'none'
             WHEN inc::float/(inc+dec) >= ${BAL_THR} THEN 'inc_majority'
             WHEN dec::float/(inc+dec) >= ${BAL_THR} THEN 'dec_majority'
             ELSE 'balanced'
           END AS balance_flag
    FROM base
  )
  SELECT gene_symbol, inc, dec, total_expr, round(inc_frac::numeric,3) AS inc_frac,
         round(dec_frac::numeric,3) AS dec_frac, balance_flag
  FROM agg
  ORDER BY total_expr DESC, gene_symbol
  LIMIT ${TOPN}
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_expr_balance_genes.csv"

# === Top chemicals by expression-edge volume ===
$PSQL -c "\copy (
  WITH base AS (
    SELECT gtc.chem_id,
           COALESCE(c.name, c.mesh_id, gtc.chem_id) AS chem_name,
           SUM( (gtc.action_norm ~* '(^|\\|)increases\\^expression(\\||$)')::int ) AS inc,
           SUM( (gtc.action_norm ~* '(^|\\|)decreases\\^expression(\\||$)')::int ) AS dec
    FROM public.gene_to_chemical gtc
    LEFT JOIN public.chemicals c ON c.chem_id = gtc.chem_id
    GROUP BY 1,2
  ),
  agg AS (
    SELECT chem_id, chem_name,
           inc, dec,
           (inc+dec) AS total_expr,
           CASE WHEN (inc+dec)>0 THEN inc::float/(inc+dec) ELSE 0 END AS inc_frac,
           CASE WHEN (inc+dec)>0 THEN dec::float/(inc+dec) ELSE 0 END AS dec_frac,
           CASE
             WHEN (inc+dec)=0 THEN 'none'
             WHEN inc::float/(inc+dec) >= ${BAL_THR} THEN 'inc_majority'
             WHEN dec::float/(inc+dec) >= ${BAL_THR} THEN 'dec_majority'
             ELSE 'balanced'
           END AS balance_flag
    FROM base
  )
  SELECT chem_id, chem_name, inc, dec, total_expr, round(inc_frac::numeric,3) AS inc_frac,
         round(dec_frac::numeric,3) AS dec_frac, balance_flag
  FROM agg
  ORDER BY total_expr DESC, chem_name NULLS LAST, chem_id
  LIMIT ${TOPN}
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_expr_balance_chemicals.csv"

# === Sentinels (optional showcase) ===
SENTINELS="${SENTINELS:-TP53,APOE,PCSK9}"
$PSQL -c "\copy (
  SELECT * FROM (
    SELECT * FROM (
      WITH base AS (
        SELECT gtc.gene_symbol,
               SUM( (gtc.action_norm ~* '(^|\\|)increases\\^expression(\\||$)')::int ) AS inc,
               SUM( (gtc.action_norm ~* '(^|\\|)decreases\\^expression(\\||$)')::int ) AS dec
        FROM public.gene_to_chemical gtc
        GROUP BY 1
      ),
      agg AS (
        SELECT gene_symbol,
               inc, dec,
               (inc+dec) AS total_expr,
               CASE WHEN (inc+dec)>0 THEN inc::float/(inc+dec) ELSE 0 END AS inc_frac,
               CASE WHEN (inc+dec)>0 THEN dec::float/(inc+dec) ELSE 0 END AS dec_frac,
               CASE
                 WHEN (inc+dec)=0 THEN 'none'
                 WHEN inc::float/(inc+dec) >= ${BAL_THR} THEN 'inc_majority'
                 WHEN dec::float/(inc+dec) >= ${BAL_THR} THEN 'dec_majority'
                 ELSE 'balanced'
               END AS balance_flag
        FROM base
      )
      SELECT gene_symbol, inc, dec, total_expr, round(inc_frac::numeric,3) AS inc_frac,
             round(dec_frac::numeric,3) AS dec_frac, balance_flag
      FROM agg
    ) t
    WHERE gene_symbol = ANY (string_to_array('${SENTINELS}',','))
    ORDER BY total_expr DESC, gene_symbol
    LIMIT 50
  ) s
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_expr_balance_sentinels.csv"

echo "[ok] Wrote:"
ls -lh "$OUTDIR"/ctd_expr_balance_*.csv
