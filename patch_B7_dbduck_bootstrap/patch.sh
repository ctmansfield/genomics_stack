#!/usr/bin/env bash
# shellcheck shell=bash
# Exposed env: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR
set -euo pipefail

patch_install() {
  echo "[${PATCH_CODE}] install: bootstrapping DuckDB schema"
  python3 "$REPO_ROOT/components/dbduck/duckdb_cli.py" bootstrap
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify: computing schema fingerprint"
  python - <<'PY'
import os, sys
repo = os.environ.get("REPO_ROOT","/mnt/nas_storage/repos/genomics-stack")
sys.path.insert(0, repo)
from components.dbduck.duck import schema_hash
print(f"schema_hash:{schema_hash()}")
PY
  echo "[${PATCH_CODE}] verify_ok"
}
