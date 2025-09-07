#!/usr/bin/env bash
set -euo pipefail
: "${NAS_ROOT:?}"
: "${REPO_ROOT:?}"

# Ensure input dir exists (ok if empty)
mkdir -p "${NAS_ROOT}/data/samples_raw"

# Run manifest builder (idempotent)
python3 "$REPO_ROOT/components/ingest/build_manifest.py" "${NAS_ROOT}/data/samples_raw"

# Print where the file landed for today
DATE=$(date +%Y%m%d)
P="${NAS_ROOT}/data/staging/${DATE}/staging_manifest.parquet"
test -f "$P" || { echo "missing $P"; exit 1; }

echo "verify_ok"
