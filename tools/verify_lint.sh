#!/usr/bin/env bash
# lint-baseline-v1 (patched verifier)
set -euo pipefail

REPO_ROOT="${1:-/root/genomics-stack}"
cd "$REPO_ROOT"

# Ensure tools exist
if ! command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit is not installed. Run: python -m pip install --upgrade pre-commit"
  exit 1
fi
if ! command -v ruff >/dev/null 2>&1; then
  echo "ruff is not installed. Run: python -m pip install --upgrade ruff"
  exit 1
fi

# Versions
PRECOMMIT_VER="$(pre-commit --version | awk '{print $2}')"
RUFF_VER="$(ruff --version | awk '{print $2}')"

# Hook revs (robust parsing with grep+sed)
get_rev () {
  local needle="$1"
  grep -A3 "$needle" .pre-commit-config.yaml 2>/dev/null \
    | sed -n 's/^[[:space:]]*rev:[[:space:]]*//p' \
    | head -n1 | tr -d '"'
}
RUFF_HOOK_REV="$(get_rev 'astral-sh/ruff-pre-commit' || true)"
SHELLCHECK_REV="$(get_rev 'shellcheck-py' || true)"
SHFMT_REV="$(get_rev 'pre-commit-shfmt' || true)"

# Run checks (don't abort; we want summary)
set +e
pre-commit run --all-files -v >/dev/null
PC_STATUS=$?
ruff --config .ruff.toml format --check . >/dev/null 2>&1
FMT_STATUS=$?
set -e

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'detached')"
CHANGES="$(git status --porcelain | wc -l | tr -d ' ')"
CI_EXISTS=$([ -f ".github/workflows/lint.yml" ] && echo true || echo false)
MAKE_SENTINEL=$([ -f Makefile ] && grep -q 'lint-baseline-v1' Makefile && echo true || echo false)

STATUS_JSON=$(cat <<JSON
{
  "patch_id": "lint-baseline-v1",
  "repo_root": "$(pwd)",
  "branch": "$BRANCH",
  "precommit_version": "$PRECOMMIT_VER",
  "ruff_version": "$RUFF_VER",
  "ruff_hook_rev": "${RUFF_HOOK_REV:-unknown}",
  "shellcheck_rev": "${SHELLCHECK_REV:-unknown}",
  "shfmt_rev": "${SHFMT_REV:-unknown}",
  "precommit_status": "$([ "$PC_STATUS" -eq 0 ] && echo passed || echo failed)",
  "format_status": "$([ "$FMT_STATUS" -eq 0 ] && echo clean || echo needs_changes)",
  "git_unstaged_changes": $CHANGES,
  "ci_workflow_present": $CI_EXISTS,
  "make_targets_present": $MAKE_SENTINEL,
  "timestamp": "$(date -u +%FT%TZ)"
}
JSON
)

ENCODED=$(printf '%s' "$STATUS_JSON" | base64 | tr -d '\n')
echo "===== GENOMICS-STACK PATCH SUMMARY ====="
echo "PASTE-THIS v1: $ENCODED"
echo "========================================"
