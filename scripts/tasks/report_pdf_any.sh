#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

cmd_report_pdf_any(){
  local upload="${1:-}"; [[ -n "$upload" ]] || { echo "usage: genomicsctl.sh report-pdf-any <upload_id>"; exit 2; }
  local ROOT=${ROOT:-/root/genomics-stack}
  local REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}
  local DIR="$REPORTS_DIR/upload_${upload}"

  # pick the highest-N top*.html if not provided env FILE
  local html="${FILE:-}"
  if [[ -z "$html" ]]; then
    html=$(ls -1t "$DIR"/top*.html 2>/dev/null | sort -V | tail -n1 || true)
  fi
  [[ -n "$html" && -f "$html" ]] || { echo "[error] no top*.html found in $DIR"; exit 3; }

  local pdf="${html%.html}.pdf"

  echo "[+] Rendering $html → $pdf"
  docker run --rm -v "$DIR":/data zenika/alpine-chrome:124 \
     --no-sandbox --headless --disable-gpu --print-to-pdf="/data/$(basename "$pdf")" "file:///data/$(basename "$html")"

  echo "[ok] PDF: $pdf"
}

register_task "report-pdf-any" "Render latest top*.html to PDF" "cmd_report_pdf_any"
