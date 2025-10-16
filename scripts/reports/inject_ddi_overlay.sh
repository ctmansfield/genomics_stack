#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-reports/upload_2}"
HTML="$OUTDIR/ctd_report_v2.html"
BODY="$OUTDIR/ctd_ddi_patient_overlay_body.html"

[[ -f "$HTML" ]] || { echo "[error] missing $HTML"; exit 1; }
[[ -f "$BODY" ]] || { echo "[warn] no $BODY to inject; skipping"; exit 0; }

tmp="${HTML}.tmp"
awk -v body="$(sed -e 's/[&]/\\&/g' -e 's/\\/\\\\/g' "$BODY")" '
  BEGIN{done=0}
  /<h2>Expression Balance<\/h2>/ && !done {
    print; print "<!-- BEGIN: DDI Overlay embed -->"; print body; print "<!-- END: DDI Overlay embed -->"; done=1; next
  }
  { print }
  END{
    if(!done){
      print "<!-- BEGIN: DDI Overlay embed -->"
      print body
      print "<!-- END: DDI Overlay embed -->"
    }
  }
' "$HTML" > "$tmp" && mv "$tmp" "$HTML"
echo "[ok] injected DDI overlay into $HTML"
