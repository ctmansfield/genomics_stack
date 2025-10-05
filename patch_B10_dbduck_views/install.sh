#!/usr/bin/env bash
set -euo pipefail
: "${REPO_ROOT:?}"
: "${NAS_ROOT:?}"

python3 "$REPO_ROOT/components/dbduck/duckdb_cli.py" bootstrap
python3 "$REPO_ROOT/components/dbduck/run_sql.py" "$REPO_ROOT/components/dbduck/sql/views_latest.sql"
echo "install_ok"
