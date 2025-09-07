#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# Exposed: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR

patch_install() {
  echo "[${PATCH_CODE}] install: create/update latest-per-sample views"
  python3 "${REPO_ROOT}/components/dbduck/duckdb_cli.py" bootstrap
  python3 "${REPO_ROOT}/components/dbduck/run_sql.py" "${REPO_ROOT}/components/dbduck/sql/views_latest.sql"
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify: row counts for base + current views"
  python - <<'PY'
import os, sys
os.environ['REPO_ROOT']=os.environ.get('REPO_ROOT','/mnt/nas_storage/repos/genomics-stack')
sys.path.insert(0, os.environ['REPO_ROOT'])
from components.dbduck.duck import conn
with conn() as con:
    for q in [
        "SELECT 'core.files' t, COUNT(*) n FROM core.files",
        "SELECT 'core.files_current' t, COUNT(*) n FROM core.files_current",
        "SELECT 'core.samples' t, COUNT(*) n FROM core.samples",
        "SELECT 'core.samples_current' t, COUNT(*) n FROM core.samples_current",
    ]:
        t,n = con.execute(q).fetchone()
        print(f"rows({t}):{n}")
PY
  echo "[${PATCH_CODE}] verify_ok"
}
