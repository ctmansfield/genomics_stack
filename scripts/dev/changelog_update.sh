#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=${REPO_DIR:-/root/genomics-stack}
cd "$REPO_DIR"
mkdir -p docs
touch docs/CHANGELOG.md
note=$(ls -1t docs/changes/*.md 2>/dev/null | head -n1 || true)
[[ -n "$note" ]] || { echo "[warn] no change notes"; exit 0; }
title=$(head -n1 "$note" | sed 's/^# *//')
date=$(grep -m1 '^Date:' "$note" | sed 's/^Date:\s*//')
printf '\n## %s (%s)\n\n- See %s\n' "$title" "$date" "${note#./}" >> docs/CHANGELOG.md
echo "[ok] CHANGELOG.md updated"
