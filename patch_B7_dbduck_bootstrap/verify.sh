#!/usr/bin/env bash
set -euo pipefail
: "${DUCKDB_PATH:?set DUCKDB_PATH}"; : "${REPO_ROOT:?set REPO_ROOT}"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["REPO_ROOT"])
from components.dbduck.duck import schema_hash
h = schema_hash()
print(f"schema_hash:{h}")
print("verify_ok")
PY
