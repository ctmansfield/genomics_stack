#!/usr/bin/env bash
# Patient-scoped gene annotations rollup from annotated variants (VEP).
# - Uses current shell DB env + PGOPTIONS (already set by your venv/workflow).
# - Does NOT load any env files. No strict mode; never 'exit'.
# - Outputs: reports/upload_2/gene_annotations.csv + *_body.html + .html
#
# Table + column mappings:
#   ANN_TABLE            (REQUIRED) e.g., public.vep_variants
#   GENE_COL             default: gene_symbol
#   CONSEQUENCE_COL      default: consequence
#   IMPACT_COL           default: impact
#   CLINVAR_SIG_COL      default: clinvar_significance
#   SIFT_COL             default: sift_pred
#   POLYPHEN_COL         default: polyphen_pred
#   HGVSP_COL            default: hgvsp
#   HGVSC_COL            default: hgvsc
#
# Example:
#   ANN_TABLE=vep.vep_variants GENE_COL=symbol CLINVAR_SIG_COL=clin_sig \
#   PGOPTIONS='-c app.patient_upload_id=2' scripts/reports/add_gene_annotations.sh

note(){ echo "[gene_annotations_export] $1" >&2; }
fail(){ echo "[gene_annotations_export] ERROR: $1" >&2; failed=1; }

failed=0
OUTDIR="reports/upload_2"
CSV="$OUTDIR/gene_annotations.csv"
HTML_BODY="$OUTDIR/gene_annotations_body.html"
HTML_PAGE="$OUTDIR/gene_annotations.html"

# ---- Required: where your annotated variants live
: "${ANN_TABLE:?Set ANN_TABLE to your variants table, e.g. public.vep_variants}"

# ---- Column mappings (override if your names differ)
: "${GENE_COL:=gene_symbol}"
: "${CONSEQUENCE_COL:=consequence}"
: "${IMPACT_COL:=impact}"
: "${CLINVAR_SIG_COL:=clinvar_significance}"
: "${SIFT_COL:=sift_pred}"
: "${POLYPHEN_COL:=polyphen_pred}"
: "${HGVSP_COL:=hgvsp}"
: "${HGVSC_COL:=hgvsc}"

mkdir -p "$OUTDIR" || fail "Cannot ensure $OUTDIR"
[ "${failed:-0}" -eq 0 ] || { echo "[gene_annotations_export] Aborting."; return 1 2>/dev/null || exit 1; }

PSQL="psql -v ON_ERROR_STOP=1 -A -F, -q"

# Build SQL with your mapped columns.
read -r -d '' SQL_ROLLUP <<SQL
WITH genes AS (
  SELECT DISTINCT UPPER(gene_symbol) AS gene_symbol
  FROM public.v_patient_genes_active
  WHERE COALESCE(gene_symbol,'') <> ''
),
vep AS (
  SELECT
    UPPER(COALESCE(${GENE_COL}, '')) AS gene_symbol,
    COALESCE(${CONSEQUENCE_COL},'') AS consequence,
    COALESCE(${IMPACT_COL},'') AS impact,
    COALESCE(${CLINVAR_SIG_COL},'') AS clinvar_significance,
    COALESCE(${SIFT_COL},'') AS sift_pred,
    COALESCE(${POLYPHEN_COL},'') AS polyphen_pred,
    COALESCE(${HGVSP_COL}, COALESCE(${HGVSC_COL},'')) AS protein_change
  FROM ${ANN_TABLE}
)
, joined AS (
  SELECT g.gene_symbol, v.*
  FROM genes g
  LEFT JOIN vep v ON v.gene_symbol = g.gene_symbol
)
, binned AS (
  SELECT
    gene_symbol,
    (gene_symbol <> '')::int AS has_variant,
    (consequence ILIKE '%stop_gained%' OR consequence ILIKE '%frameshift%' OR consequence ILIKE '%splice_acceptor%' OR consequence ILIKE '%splice_donor%' OR consequence ILIKE '%start_lost%')::int AS lof_bin,
    (consequence ILIKE '%missense_variant%')::int AS missense_bin,
    (consequence ILIKE '%synonymous_variant%')::int AS syn_bin,
    (clinvar_significance ILIKE '%pathogenic%' AND clinvar_significance NOT ILIKE '%uncertain%')::int AS clinvar_path_bin,
    (clinvar_significance ILIKE '%likely_pathogenic%')::int AS clinvar_lpath_bin,
    (sift_pred ILIKE '%deleterious%')::int AS sift_damaging_bin,
    (polyphen_pred ILIKE '%probably_damaging%' OR polyphen_pred ILIKE '%possibly_damaging%')::int AS polyphen_damaging_bin,
    NULLIF(protein_change,'') AS exemplar_change
  FROM joined
)
, agg AS (
  SELECT
    gene_symbol,
    SUM(has_variant)::int AS variants_n,
    SUM(lof_bin)::int AS lof_n,
    SUM(missense_bin)::int AS missense_n,
    SUM(syn_bin)::int AS synonymous_n,
    SUM(clinvar_path_bin + clinvar_lpath_bin)::int AS clinvar_path_like_n,
    SUM(sift_damaging_bin)::int AS sift_damaging_n,
    SUM(polyphen_damaging_bin)::int AS polyphen_damaging_n,
    (array_agg(DISTINCT exemplar_change) FILTER (WHERE exemplar_change IS NOT NULL))[1:5] AS exemplars_arr
  FROM binned
  GROUP BY gene_symbol
)
SELECT
  g.gene_symbol,
  COALESCE(a.variants_n,0) AS variants_n,
  COALESCE(a.lof_n,0) AS lof_n,
  COALESCE(a.missense_n,0) AS missense_n,
  COALESCE(a.synonymous_n,0) AS synonymous_n,
  COALESCE(a.clinvar_path_like_n,0) AS clinvar_path_like_n,
  COALESCE(a.sift_damaging_n,0) AS sift_damaging_n,
  COALESCE(a.polyphen_damaging_n,0) AS polyphen_damaging_n,
  COALESCE(array_to_string(a.exemplars_arr, '; '), '') AS exemplar_changes
FROM public.v_patient_genes_active g0
JOIN (SELECT DISTINCT UPPER(gene_symbol) AS gene_symbol FROM public.v_patient_genes_active) g USING (gene_symbol)
LEFT JOIN agg a USING (gene_symbol)
ORDER BY g.gene_symbol;
SQL

note "Exporting gene annotations CSV from ${ANN_TABLE} ..."
echo "gene_symbol,variants_n,lof_n,missense_n,synonymous_n,clinvar_path_like_n,sift_damaging_n,polyphen_damaging_n,exemplar_changes" > "$CSV" || fail "Cannot write $CSV"
echo "$SQL_ROLLUP" | $PSQL >> "$CSV" || fail "psql export failed"

[ "${failed:-0}" -eq 0 ] || { echo "[gene_annotations_export] Aborting after CSV error."; return 1 2>/dev/null || exit 1; }

# HTML body
note "Rendering HTML body..."
{
  echo '<!--GENE_ANNOTATIONS:BEGIN-->'
  echo '<section id="gene-annotations"><h2>Gene Annotations (Patient-Scoped)</h2>'
  echo '<p>Rollup from annotated variants (VEP). Counts are per gene.</p>'
  echo '<table border="1" cellpadding="4" cellspacing="0">'
  echo '<thead><tr><th>Gene</th><th>Variants</th><th>LoF</th><th>Missense</th><th>Synonymous</th><th>ClinVar P/LP</th><th>SIFT dmg</th><th>PolyPhen dmg</th><th>Exemplars</th></tr></thead><tbody>'
  tail -n +2 "$CSV" | while IFS=, read -r gene v lo m s cv sd pd ex; do
    echo "<tr><td>${gene}</td><td>${v}</td><td>${lo}</td><td>${m}</td><td>${s}</td><td>${cv}</td><td>${sd}</td><td>${pd}</td><td>${ex}</td></tr>"
  done
  echo '</tbody></table></section>'
  echo '<!--GENE_ANNOTATIONS:END-->'
} > "$HTML_BODY" || fail "Cannot write $HTML_BODY"

# Standalone page wrapper
note "Rendering standalone HTML page..."
{
  echo '<!doctype html><html><head><meta charset="utf-8"><title>Gene Annotations</title></head><body>'
  cat "$HTML_BODY"
  echo '</body></html>'
} > "$HTML_PAGE" || fail "Cannot write $HTML_PAGE"

[ "${failed:-0}" -eq 0 ] && note "Wrote $CSV, $HTML_BODY, $HTML_PAGE"
# end
