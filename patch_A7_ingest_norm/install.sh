#!/usr/bin/env bash
set -euo pipefail
: "${NAS_ROOT:?}"
: "${REPO_ROOT:?}"
python3 "$REPO_ROOT/components/ingest/build_manifest.py" "${NAS_ROOT}/data/samples_raw" || true
echo "install_ok"
