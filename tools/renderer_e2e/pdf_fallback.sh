#!/usr/bin/env bash
set -euo pipefail
HTML="${1:?html input}"
PDF="${2:?pdf output}"
: "${WKHTMLTOPDF:=wkhtmltopdf}"
"$WKHTMLTOPDF" "$HTML" "$PDF"
echo "[pdf_fallback] wrote $PDF"
