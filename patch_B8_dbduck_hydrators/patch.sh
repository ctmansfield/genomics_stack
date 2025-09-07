#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# Exposed: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR

patch_install() {
  echo "[${PATCH_CODE}] install: ensure data dirs (variants/annotations)"
  mkdir -p "${NAS_ROOT}/data/variants" "${NAS_ROOT}/data/annotations"
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify: bootstrap + hydrate + row counts"
  python3 "${REPO_ROOT}/components/dbduck/duckdb_cli.py" bootstrap
  python3 "${REPO_ROOT}/components/dbduck/duckdb_cli.py" hydrate-from-parquet
  python - <<'PY'
import os, sys
os.environ['REPO_ROOT']=os.environ.get('REPO_ROOT','/mnt/nas_storage/repos/genomics-stack')
sys.path.insert(0, os.environ['REPO_ROOT'])
from components.dbduck.duck import conn
with conn() as con:
    for t in ["core.files","core.samples","core.variants","core.annotations"]:
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"rows({t}):{n}")
PY
  echo "[${PATCH_CODE}] verify_ok"
}
