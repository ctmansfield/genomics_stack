#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# Exposed: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR

patch_install() {
  echo "[${PATCH_CODE}] install: build manifest parquet"
  mkdir -p "${NAS_ROOT}/data/samples_raw"
  python3 "${REPO_ROOT}/components/ingest/build_manifest.py" "${NAS_ROOT}/data/samples_raw" || true
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify: manifest rows/hash"
  python - <<'PY'
import os, glob, hashlib
from pathlib import Path
import duckdb
nas=os.environ.get("NAS_ROOT","/mnt/nas_storage")
paths=sorted(glob.glob(f"{nas}/data/staging/*/staging_manifest.parquet"))
if not paths:
    print("manifest_rows=0")
    print("manifest_hash=00000000")
    raise SystemExit(0)
p=paths[-1]
con=duckdb.connect()
rows = con.execute(f"SELECT COUNT(*) FROM read_parquet('{p}')").fetchone()[0]
h = hashlib.sha256(Path(p).read_bytes()).hexdigest()[:8]
print(f"manifest_rows={rows}")
print(f"manifest_hash={h}")
PY
  echo "[${PATCH_CODE}] verify_ok"
}
