#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/nas_storage}"
BOOT="$ROOT/tools/vep_cache_bootstrap.sh"
CACHE_DIR="${CACHE_DIR:-$ROOT/vep/cache}"
REF_DIR="${REF_DIR:-$ROOT/vep/reference}"

# Default to known-good; can be overridden by env
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_111.0}"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; shift; fi

has_existing=0
[[ -d "$CACHE_DIR" && -n "$(ls -A "$CACHE_DIR" 2>/dev/null || true)" ]] && has_existing=1
[[ -d "$REF_DIR"   && -n "$(ls -A "$REF_DIR"   2>/dev/null || true)" ]] && has_existing=1

echo "==> VEP Guard"
echo "  CACHE_DIR: $CACHE_DIR"
echo "  REF_DIR:   $REF_DIR"
echo "  VEP_IMAGE: $VEP_IMAGE"
echo

if (( has_existing == 1 && FORCE == 0 )); then
  echo "Existing VEP cache/reference detected."
  echo "This may re-download or overwrite files if releases differ."
  read -r -p "Proceed with bootstrap using '$VEP_IMAGE'? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) echo "Proceeding...";;
    *) echo "Aborted by user."; exit 0;;
  esac
fi

# Respect DRY_RUN
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY RUN] Would run with VEP_IMAGE='$VEP_IMAGE': $BOOT $*"
  exit 0
fi

# Execute the underlying bootstrap with the pinned/selected image
VEP_IMAGE="$VEP_IMAGE" "$BOOT" "$@"
