#!/usr/bin/env bash
# Guess VEP column names for a given table and print a ready-to-run command line.
# Usage:
#   scripts/reports/guess_vep_columns.sh public.some_table
# Notes: no strict mode; never 'exit'.

if [ -z "$1" ]; then
  echo "[guess_vep_columns] Usage: $0 <schema.table>" >&2
  return 1 2>/dev/null || exit 1
fi

TBL="$1"

# Pull column names
COLS=$(psql -At -c "SELECT column_name FROM information_schema.columns WHERE table_schema = split_part('$TBL','.',1) AND table_name = split_part('$TBL','.',2);" || true)

have() { echo "$COLS" | grep -ixq "$1"; }

pick() {
  # pick first existing from the list
  for c in "$@"; do if have "$c"; then echo "$c"; return; fi; done
  echo ""  # none
}

GENE=$(pick gene_symbol symbol gene hgnc_symbol gene_name)
CSQ=$(pick consequence consequences most_severe_consequence csq)
IMPACT=$(pick impact variant_impact)
CLIN=$(pick clinvar_significance clin_sig clinvar_clinsig clinsig)
SIFT=$(pick sift_pred sift_prediction sift)
POLY=$(pick polyphen_pred polyphen_prediction polyphen)
HGVSP=$(pick hgvsp hgvsp_short protein_change aa_change)
HGVSC=$(pick hgvsc hgvsc_short coding_change cdna_change)

echo "[guess_vep_columns] Columns on $TBL:"
echo "  gene:     ${GENE:-<none>}"
echo "  csq:      ${CSQ:-<none>}"
echo "  impact:   ${IMPACT:-<none>}"
echo "  clinvar:  ${CLIN:-<none>}"
echo "  sift:     ${SIFT:-<none>}"
echo "  polyphen: ${POLY:-<none>}"
echo "  hgvsp:    ${HGVSP:-<none>}"
echo "  hgvsc:    ${HGVSC:-<none>}"
echo

CMD="ANN_TABLE=$TBL"
[ -n "$GENE" ]  && CMD+=" GENE_COL=$GENE"
[ -n "$CSQ" ]   && CMD+=" CONSEQUENCE_COL=$CSQ"
[ -n "$IMPACT" ]&& CMD+=" IMPACT_COL=$IMPACT"
[ -n "$CLIN" ]  && CMD+=" CLINVAR_SIG_COL=$CLIN"
[ -n "$SIFT" ]  && CMD+=" SIFT_COL=$SIFT"
[ -n "$POLY" ]  && CMD+=" POLYPHEN_COL=$POLY"
[ -n "$HGVSP" ] && CMD+=" HGVSP_COL=$HGVSP"
[ -n "$HGVSC" ] && CMD+=" HGVSC_COL=$HGVSC"

echo "[guess_vep_columns] Try:"
echo "PGOPTIONS='-c app.patient_upload_id=2' \\"
echo "$CMD \\"
echo "scripts/reports/add_gene_annotations.sh"
