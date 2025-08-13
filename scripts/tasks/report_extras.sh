#!/usr/bin/env bash
# shellcheck shell=bash

# Print exact report paths for an upload_id (and sizes if present)
cmd_report_open() {
  local upload_id="${1:-}"; [[ -n "$upload_id" ]] || die "Usage: genomicsctl.sh report-open <upload_id>"
  local dir="${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}/upload_${upload_id}"
  local html="$dir/top5.html"
  local tsv="$dir/top5.tsv"
  local pdf="$dir/top5.pdf"

  say "[+] Report directory: $dir"
  for f in "$html" "$tsv" "$pdf"; do
    if [[ -f "$f" ]]; then
      printf "  %s\t(%s bytes, mtime %s)\n" "$f" "$(stat -c '%s' "$f")" "$(stat -c '%y' "$f")"
    else
      printf "  %s\t[missing]\n" "$f"
    fi
  done
  ok "Done."
}

# Quiet wrapper around the existing report-pdf task (filters Chromium noise)
cmd_report_pdf_quiet() {
  local upload_id="${1:-}"; [[ -n "$upload_id" ]] || die "Usage: genomicsctl.sh report-pdf-quiet <upload_id>"
  if [[ -z "${TASK_FN[report-pdf]+x}" ]]; then
    die "Underlying task 'report-pdf' not found. Generate the report PDF the usual way."
  fi
  local __fn="${TASK_FN[report-pdf]}"

  # run the original task but filter noisy stderr lines
  {
    "$__fn" "$upload_id"
  } 2> >(grep -v 'Failed to connect to the bus' \
        | grep -v 'sandbox_linux' \
        | grep -v 'config_dir_policy_loader' \
        | grep -v 'Floss manager not present' \
        | grep -v 'AttributionReportingCrossAppWeb' \
        || true)
}

register_task "report-open"       "Show paths & sizes for an upload's report"  "cmd_report_open"
register_task "report-pdf-quiet"  "Render PDF with filtered Chromium logs"     "cmd_report_pdf_quiet"
