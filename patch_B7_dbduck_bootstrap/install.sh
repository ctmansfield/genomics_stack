#!/usr/bin/env bash
set -euo pipefail
: "${DUCKDB_PATH:?set DUCKDB_PATH}"; : "${REPO_ROOT:?set REPO_ROOT}"
python3 - <<'PY'
import os, sys
from pathlib import Path
Path(os.environ["DUCKDB_PATH"]).parent.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, os.environ["REPO_ROOT"])
from components.dbduck.duck import bootstrap
bootstrap(os.path.join(os.environ["REPO_ROOT"], "components/dbduck/bootstrap.sql"))
print("install_ok")
PY
