#!/usr/bin/env bash
set -euo pipefail
: "${REPO_ROOT:?}"; : "${DUCKDB_PATH:?}"

python3 "$REPO_ROOT/components/dbduck/duckdb_cli.py" bootstrap
