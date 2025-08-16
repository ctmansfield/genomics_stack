#!/usr/bin/env bash
set -euo pipefail
FID="${1:?Usage: make_pdf.sh <file_id> [rows]}" ; ROWS="${2:-100}"
PY=/root/genomics-stack/tools/reports/make_pdf_report.py
python "$PY" --file-id "$FID" --report-dir /root/genomics-stack/risk_reports/out --max-full-rows "$ROWS"
