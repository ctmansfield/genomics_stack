#!/usr/bin/env bash
# Clinician-facing Top-N report (system coverage, explanations)
set -euo pipefail

cmd_report_clinician_top20() {
  local upload_id="${1:-}"; local n="${2:-20}"
  [[ -n "$upload_id" ]] || { echo "usage: report-clinician-top20 <upload_id> [N]"; exit 2; }

  # Resolve repo root from this script's location if ROOT not provided
  local SCRIPT_DIR ROOT
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Repo root is two levels up from scripts/tasks
  ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

  # Default reports dir to repo-local if not provided
  local REPORTS_DIR
  REPORTS_DIR="${REPORTS_DIR:-$ROOT/reports}"
  local OUT_DIR="$REPORTS_DIR/upload_${upload_id}"
  mkdir -p "$OUT_DIR"

  local OUT_HTML="$OUT_DIR/clinician_top${n}.html"

  # Use PG_DSN if set; otherwise try to infer from genomicsctl.sh default HDB
  if [[ -z "${PG_DSN:-}" ]]; then
    local CANDIDATES=(
      "$ROOT/scripts/genomicsctl.sh"
      "$ROOT/scripts/scripts/genomicsctl.sh"
    )
    for f in "${CANDIDATES[@]}"; do
      if [[ -f "$f" ]]; then
        local HDB
        HDB=$(grep -E "^: \${HDB" "$f" | sed -E "s/.*\{HDB:=([^}]*)\}.*/\1/") || true
        if [[ -n "$HDB" ]]; then
          export PG_DSN="$HDB"
          break
        fi
      fi
    done
  fi

  [[ -n "${PG_DSN:-}" ]] || { echo "PG_DSN not set; export PG_DSN or edit $ROOT/scripts/genomicsctl.sh"; exit 3; }

  echo "[+] Building Clinician Top-${n} for upload_id=${upload_id} -> $OUT_HTML"
  local PYTHON
  PYTHON="${PYTHON:-python}"
  if [[ -x "$ROOT/.venv_gs2/bin/python" ]]; then
    PYTHON="$ROOT/.venv_gs2/bin/python"
  fi
  "$PYTHON" "$ROOT/scripts/reports/clinician_top20.py" \
    --upload-id "$upload_id" \
    --limit "$n" \
    --dsn "$PG_DSN" \
    --out-html "$OUT_HTML"

  echo "[ok] HTML: $OUT_HTML"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd_report_clinician_top20 "${1:-}" "${2:-20}"
  exit $?
fi

if declare -F register_task >/dev/null 2>&1; then
  register_task "report-clinician-top20" "Build clinician Top-N report (system coverage)" "cmd_report_clinician_top20"
fi
