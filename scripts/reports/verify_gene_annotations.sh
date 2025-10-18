#!/usr/bin/env bash
# Verifies gene annotation artifacts and injection presence.

fail(){ echo "[verify_gene_annotations] FAIL: $1" >&2; failed=1; }
ok(){   echo "[verify_gene_annotations] OK: $1" >&2; }

failed=0
OUTDIR="reports/upload_2"
CSV="$OUTDIR/gene_annotations.csv"
BODY="$OUTDIR/gene_annotations_body.html"
PAGE="$OUTDIR/gene_annotations.html"
RHTML="$OUTDIR/ctd_report_v2.html"

[ -s "$CSV" ]  || fail "Missing/empty $CSV"
[ -s "$BODY" ] || fail "Missing/empty $BODY"
[ -s "$PAGE" ] || fail "Missing/empty $PAGE"
[ -s "$RHTML" ]|| fail "Missing/empty $RHTML"

# Block must appear exactly once
BEGIN_CNT=$(grep -c '<!--GENE_ANNOTATIONS:BEGIN-->' "$RHTML")
END_CNT=$(grep -c '<!--GENE_ANNOTATIONS:END-->' "$RHTML")
if [ "$BEGIN_CNT" -ne 1 ] || [ "$END_CNT" -ne 1 ]; then
  fail "Gene Annotations block not found exactly once (begin=$BEGIN_CNT end=$END_CNT)"
fi

[ "${failed:-0}" -eq 0 ] && ok "Gene Annotations CSV/HTML present and injected once."
[ "${failed:-0}" -eq 0 ] || echo "[verify_gene_annotations] See messages above." >&2
# end
