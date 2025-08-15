#!/usr/bin/env bash
set -euo pipefail
# Wrapper: try native 'vep' first; otherwise run Docker image with mounted cache/reference.
CACHE_DIR="${CACHE_DIR:-/mnt/nas_storage/vep/cache}"
REF_DIR="${REF_DIR:-/mnt/nas_storage/vep/reference}"
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_111.0}"

if command -v vep >/dev/null 2>&1; then
  exec vep "$@"
fi

# Prefer docker, fall back to podman
engine=""
if command -v docker >/dev/null 2>&1; then engine="docker"
elif command -v podman >/dev/null 2>&1; then engine="podman"
else
  echo "[ERR] Neither 'vep' nor a container engine (docker/podman) found." >&2
  exit 127
fi

# Run containerized vep; mount cache+ref and current working dir
exec "$engine" run --rm \
  -v "$CACHE_DIR":"$CACHE_DIR":ro \
  -v "$REF_DIR":"$REF_DIR":ro \
  -v "$PWD":"$PWD" \
  -w "$PWD" \
  -e "PERL5LIB=/opt/vep/.vep" \
  "$VEP_IMAGE" vep "$@"
