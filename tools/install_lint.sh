#!/usr/bin/env bash
# tools/install_lint.sh — lint-hotfix-v1
set -euo pipefail

REPO_ROOT="${1:-/root/genomics-stack}"
cd "$REPO_ROOT"

python -m pip install --upgrade pip >/dev/null
python -m pip install --upgrade pre-commit ruff >/dev/null

pre-commit install

echo "Ruff: $(ruff --version)"
echo "pre-commit: $(pre-commit --version)"
