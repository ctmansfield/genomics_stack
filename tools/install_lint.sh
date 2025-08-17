\
#!/usr/bin/env bash
# lint-baseline-v1
set -euo pipefail

REPO_ROOT="${1:-/root/genomics-stack}"
cd "$REPO_ROOT"

# Python tools
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install --upgrade pre-commit ruff >/dev/null

# Install the git hook
pre-commit install

echo "Ruff: $(ruff --version)"
echo "pre-commit: $(pre-commit --version)"
echo "Hook installed into .git/hooks/pre-commit"

# Summarize in the same one-line format
"$(dirname "$0")/verify_lint.sh" "$REPO_ROOT"
