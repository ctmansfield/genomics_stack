#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="/root/genomics-stack"
if [[ -d "$ROOT_DIR/env.d" ]]; then
  for f in "$ROOT_DIR"/env.d/*.env; do [[ -f "$f" ]] && source "$f"; done
fi
[[ -f "$ROOT_DIR/.env.local" ]] && source "$ROOT_DIR/.env.local"
return 0
