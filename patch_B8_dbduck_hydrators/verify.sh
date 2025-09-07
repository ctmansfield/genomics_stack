#!/usr/bin/env bash
set -euo pipefail
: "${REPO_ROOT:?}"; : "${DUCKDB_PATH:?}"
python3 "$REPO_ROOT/components/dbduck/duckdb_cli.py" hydrate-from-parquet
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["REPO_ROOT"])
from components.dbduck.duck import conn
with conn() as con:
    for t in ["core.samples","core.files","core.variants","core.annotations"]:
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"rows({t}):{n}")
print("verify_ok")
PY
