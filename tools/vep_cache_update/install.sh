#!/usr/bin/env bash
set -euo pipefail
# Purpose: prepare VEP runtime (dirs + container image) WITHOUT touching the cache,
#          unless explicitly requested. Use update_cache.sh to modify cache.
CACHE_DIR="${CACHE_DIR:-/mnt/nas_storage/vep/cache}"
REF_DIR="${REF_DIR:-/mnt/nas_storage/vep/reference}"
ASSEMBLY="${ASSEMBLY:-GRCh38}"
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_111.0}"

mkdir -p "$CACHE_DIR" "$REF_DIR"

echo "[install] Preparing VEP environment (no cache changes)"
# Pull image if possible
if command -v docker >/dev/null 2>&1; then
  echo "[install] Pulling $VEP_IMAGE via docker"
  docker pull "$VEP_IMAGE" >/dev/null
elif command -v podman >/dev/null 2>&1; then
  echo "[install] Pulling $VEP_IMAGE via podman"
  podman pull "$VEP_IMAGE" >/dev/null
else
  echo "[install] No container engine found; will try native 'vep' at runtime." >&2
fi

# Validate presence and print hints (but do NOT install)
missing=0
[[ -d "$CACHE_DIR" ]] || { echo "[warn] Missing cache dir: $CACHE_DIR"; missing=1; }
[[ -s "$REF_DIR/${ASSEMBLY}.fa" ]] || { echo "[warn] Missing FASTA: $REF_DIR/${ASSEMBLY}.fa"; missing=1; }

if [[ $missing -eq 1 ]]; then
  cat >&2 <<MSG
[warn] Cache or reference FASTA appears missing.
       (This script does not modify cache automatically.)
       To update or install cache, run:
         tools/vep_cache_update/update_cache.sh
MSG
fi

echo "[install] Done (no cache updates performed)."
