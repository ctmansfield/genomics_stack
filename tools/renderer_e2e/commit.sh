#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail
ROOT=/root/genomics-stack
LOG="$ROOT/.renderer_e2e.verify.log"
STAMP="$ROOT/.renderer_e2e.ok"

bash "$ROOT/tools/renderer_e2e/verify.sh" | tee "$LOG"
if grep -q "ALL GREEN" "$LOG"; then
  date -u +%FT%TZ > "$STAMP"
  cd "$ROOT"
  git add tools/renderer_e2e risk_reports || true
  git add "$STAMP" "$LOG" || true
  git commit -m "patch(0031): renderer PDF fix verified: $(cat "$STAMP")" || true
  echo "[commit] success"
else
  echo "[commit] verify failed; no commit" >&2
  exit 2
fi
