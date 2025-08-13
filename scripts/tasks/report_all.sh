#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT_DIR/lib/common.sh"

task_report_all() {
  local id="${1:-}"; [[ -n "$id" ]] || die "Usage: report-all <upload_id>"
  "$ROOT_DIR/genomicsctl.sh" report-top5 "$id"
  "$ROOT_DIR/genomicsctl.sh" report-pdf  "$id"
}
register_task "report-all" "Generate Top 5 report (HTML/TSV) and PDF: report-all <upload_id>" task_report_all "Convenience wrapper"
