#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

ROOT=${ROOT:-/root/genomics-stack}
REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}

die(){ echo "[error] $*" >&2; exit 1; }

cmd_report_pdf_any(){
  local upload="${1:-}"; local html="${2:-}"
  [[ -n "$upload" ]] || die "usage: genomicsctl.sh report-pdf-any <upload_id> [html_path]"
  local dir="$REPORTS_DIR/upload_${upload}"
  [[ -d "$dir" ]] || die "no report dir: $dir"

  if [[ -z "$html" ]]; then
    html=$(ls -1t "$dir"/top*.html 2>/dev/null | head -n1 || true)
    [[ -n "$html" ]] || die "no top*.html found in $dir"
  fi
  [[ -f "$html" ]] || die "not found: $html"

  local base="$(basename "$html" .html)"
  local pdf="$dir/${base}.pdf"

  echo "[+] Rendering $html → $pdf"
  docker run --rm -v "$dir":/data --shm-size=256m \
    zenika/alpine-chrome:125 \
    --no-sandbox --headless --disable-gpu --print-to-pdf="/data/$(basename "$pdf")" \
    "file:///data/$(basename "$html")" >/dev/null 2>&1 || true

  if [[ -s "$pdf" ]]; then
    echo "[ok] PDF: $pdf"
  else
    echo "[warn] Chrome print produced empty file; trying wkhtmltopdf fallback"
    docker run --rm -v "$dir":/data sosign/wkhtmltopdf wkhtmltopdf \
      "/data/$(basename "$html")" "/data/$(basename "$pdf")"
    [[ -s "$pdf" ]] && echo "[ok] PDF (wkhtmltopdf): $pdf" || die "PDF failed"
  fi
}

register_task "report-pdf-any" "Render a specific report HTML to PDF" "cmd_report_pdf_any" \
"Usage: genomicsctl.sh report-pdf-any <upload_id> [html_path]
If html_path omitted, uses newest top*.html in the upload folder."
