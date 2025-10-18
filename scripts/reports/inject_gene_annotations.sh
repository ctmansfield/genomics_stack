#!/usr/bin/env bash
# Injects the Gene Annotations HTML body into reports/upload_2/ctd_report_v2.html.
# Idempotent: replaces existing block between <!--GENE_ANNOTATIONS:BEGIN--> and END, or inserts before </body>.

note(){ echo "[inject_gene_annotations] $1" >&2; }
fail(){ echo "[inject_gene_annotations] ERROR: $1" >&2; failed=1; }

failed=0
OUTDIR="reports/upload_2"
REPORT_HTML="$OUTDIR/ctd_report_v2.html"
BODY_HTML="$OUTDIR/gene_annotations_body.html"

[ -s "$REPORT_HTML" ] || fail "Missing $REPORT_HTML"
[ -s "$BODY_HTML" ]   || fail "Missing $BODY_HTML"
[ "${failed:-0}" -eq 0 ] || { echo "[inject_gene_annotations] Aborting."; return 1 2>/dev/null || exit 1; }

# If block exists, replace it; else insert before </body> (or at end if not found)
TMP="$REPORT_HTML.tmp.$$"
if grep -q '<!--GENE_ANNOTATIONS:BEGIN-->' "$REPORT_HTML"; then
  note "Replacing existing Gene Annotations block..."
  awk -v body="$BODY_HTML" '
    BEGIN{inblk=0}
    /<!--GENE_ANNOTATIONS:BEGIN-->/ { inblk=1; while((getline line < body) > 0){ print line } next }
    /<!--GENE_ANNOTATIONS:END-->/ { inblk=0; next }
    inblk==0 { print }
  ' "$REPORT_HTML" > "$TMP" && mv "$TMP" "$REPORT_HTML" || fail "Replacement failed"
else
  note "Inserting Gene Annotations block..."
  if grep -q '</body>' "$REPORT_HTML"; then
    awk -v body="$BODY_HTML" '
      /<\/body>/ { while((getline line < body) > 0){ print line } print; next }
      { print }
    ' "$REPORT_HTML" > "$TMP" && mv "$TMP" "$REPORT_HTML" || fail "Insertion failed"
  else
    cat "$REPORT_HTML" "$BODY_HTML" > "$TMP" && mv "$TMP" "$REPORT_HTML" || fail "Append failed"
  fi
fi

[ "${failed:-0}" -eq 0 ] && note "Injected Gene Annotations into $REPORT_HTML"
# end
