#!/usr/bin/env bash
set -euo pipefail
REPO="/root/genomics-stack"
pushd "$REPO" >/dev/null
git add -A tools/vep_cache_update scripts/vep sql/schema_vep.sql
if ! git diff --cached --quiet; then
  git commit -m "VEP cache update & pipeline alignment (install→verify→commit)"
else
  echo "[commit] Nothing to commit."
fi
popd >/dev/null
echo "[commit] Done."
