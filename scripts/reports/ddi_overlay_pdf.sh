#!/usr/bin/env bash
# Render standalone DDI overlay HTML to PDF.
# Tries zenika/alpine-chrome:124 first, then falls back to wkhtmltopdf container.
# No strict mode. No 'exit'. No env sourcing.

note(){ echo "[ddi_overlay_pdf] $1" >&2; }
fail(){ echo "[ddi_overlay_pdf] ERROR: $1" >&2; failed=1; }

REPORTS_DIR="reports/upload_2"
HTML="$REPORTS_DIR/ctd_ddi_patient_overlay.html"
PDF="$REPORTS_DIR/ctd_ddi_patient_overlay.pdf"

: "${CHROME_IMG:=zenika/alpine-chrome:124}"
: "${CHROME_FLAGS:=--no-sandbox --headless=new --disable-gpu --disable-dev-shm-usage --no-first-run --disable-extensions --allow-file-access-from-files --user-data-dir=/tmp/chrome-profile}"
: "${WKHTML_IMG:=surnet/alpine-wkhtmltopdf:3.19-0.12.6-small}"

failed=0
[ -s "$HTML" ] || fail "Missing or empty $HTML"
[ "${failed:-0}" -eq 0 ] || { echo "[ddi_overlay_pdf] Aborting." >&2; return 1 2>/dev/null || exit 1; }

# Try Chrome (new headless)
note "Rendering (Chrome headless=new) $HTML => $PDF"
docker run --rm -v "$(pwd)/$REPORTS_DIR:/work" "$CHROME_IMG" \
  chromium-browser $CHROME_FLAGS \
  --print-to-pdf="/work/ctd_ddi_patient_overlay.pdf" "file:///work/ctd_ddi_patient_overlay.html"
rc=$?

# Try legacy Chrome if needed
if [ $rc -ne 0 ] || [ ! -s "$PDF" ]; then
  note "Primary Chrome render failed; retrying legacy --headless..."
  docker run --rm -v "$(pwd)/$REPORTS_DIR:/work" "$CHROME_IMG" \
    chromium-browser --no-sandbox --headless --disable-gpu --disable-dev-shm-usage --no-first-run --disable-extensions \
    --print-to-pdf="/work/ctd_ddi_patient_overlay.pdf" "file:///work/ctd_ddi_patient_overlay.html"
fi

# Fallback to wkhtmltopdf
if [ ! -s "$PDF" ]; then
  note "Chrome render failed. Falling back to wkhtmltopdf..."
  docker run --rm -v "$(pwd)/$REPORTS_DIR:/work" "$WKHTML_IMG" \
    wkhtmltopdf --enable-local-file-access "/work/ctd_ddi_patient_overlay.html" "/work/ctd_ddi_patient_overlay.pdf" || \
    fail "wkhtmltopdf fallback failed"
fi

[ -s "$PDF" ] || fail "Failed to produce $PDF"
[ "${failed:-0}" -eq 0 ] && note "Done."
# end
