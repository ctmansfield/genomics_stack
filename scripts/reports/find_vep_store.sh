#!/usr/bin/env bash
# Finds likely VEP/annotated variants tables across ALL schemas by matching common column names.
# Prints candidates ordered by match score; use the best one with guess_vep_columns.sh

psql -v ON_ERROR_STOP=1 -P pager=off -A -F $'\t' -c "
WITH cols AS (
  SELECT table_schema, table_name, column_name
  FROM information_schema.columns
),
wanted(col) AS (
  VALUES
    ('gene_symbol'),('symbol'),('gene'),('hgnc_symbol'),('gene_name'),
    ('consequence'),('consequences'),('most_severe_consequence'),('csq'),
    ('impact'),('variant_impact'),
    ('clinvar_significance'),('clin_sig'),('clinvar_clinsig'),('clinsig'),
    ('sift_pred'),('sift_prediction'),('sift'),
    ('polyphen_pred'),('polyphen_prediction'),('polyphen'),
    ('hgvsp'),('hgvsp_short'),('protein_change'),('aa_change'),
    ('hgvsc'),('hgvsc_short'),('coding_change'),('cdna_change')
),
hit AS (
  SELECT c.table_schema, c.table_name, c.column_name,
         (c.column_name IN (SELECT col FROM wanted))::int AS is_hit
  FROM cols c
)
SELECT table_schema||'.'||table_name AS table,
       SUM(is_hit) AS matched_cols,
       STRING_AGG(column_name, ',' ORDER BY column_name) AS all_cols
FROM hit
GROUP BY table_schema, table_name
HAVING SUM(is_hit) >= 3
ORDER BY matched_cols DESC, table ASC;
"
