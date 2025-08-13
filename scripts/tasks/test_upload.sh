#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT_DIR/lib/common.sh"

task_test_upload() {
  local file="${1:-}"
  local label="${2:-John_Doe}"
  local url="${PORTAL_URL:-http://localhost:8090}"

  if [[ -z "$file" ]]; then
    echo "Usage: genomicsctl.sh test-upload /path/to/file [sample_label]" >&2
    exit 2
  fi
  [[ -r "$file" ]] || { echo "File not readable: $file" >&2; exit 2; }

  say "[+] POST $url/upload"
  # -sS: quiet but show errors; -f: fail on 4xx/5xx
  curl -sS -f -X POST \
       -F "file=@${file}" \
       -F "sample_label=${label}" \
       "$url/upload" | tee /tmp/test_upload.json
  echo
  ok "Upload request sent"
}

register_task "test-upload" "Upload a file to the portal" task_test_upload \
  "Usage: test-upload /path/to/file [sample_label]"
