#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT_DIR/lib/common.sh"

task_report_pdf() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then say "Usage: report-pdf <upload_id>"; exit 2; fi
  local dir="/mnt/nas_storage/genomics-stack/reports/upload_${id}"
  local html="${dir}/top5.html"
  local pdf="${dir}/top5.pdf"
  require_readable "$html"

  sudo chown -R 1000:1000 "$dir" || true
  sudo chmod -R u+rwX,go+rX "$dir" || true

  say "[+] Rendering ${html} → ${pdf}"
  docker run --rm -u 1000:1000 \
    -v "/mnt/nas_storage/genomics-stack/reports:/data" \
    ghcr.io/zenika/alpine-chrome:with-node \
    chromium-browser --headless --no-sandbox --disable-dev-shm-usage --disable-gpu \
      --print-to-pdf=/data/upload_${id}/top5.pdf \
      file:///data/upload_${id}/top5.html

  ok "PDF written: ${pdf}"
}
register_task "report-pdf" "Render HTML → PDF for an upload (usage: report-pdf <upload_id>)" task_report_pdf "Requires existing top5.html"
