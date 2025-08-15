#!/usr/bin/env bash
set -euo pipefail
# Purpose: EXPLICIT cache install/update via Ensembl INSTALL.pl under Docker/Podman
CACHE_DIR="${CACHE_DIR:-/mnt/nas_storage/vep/cache}"
REF_DIR="${REF_DIR:-/mnt/nas_storage/vep/reference}"
ASSEMBLY="${ASSEMBLY:-GRCh38}"
SPECIES="${SPECIES:-homo_sapiens}"
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_111.0}"
CACHE_OPTS="${CACHE_OPTS:--a cf -s ${SPECIES} -y ${ASSEMBLY} --REFSEQ}"  # adjust as needed

mkdir -p "$CACHE_DIR" "$REF_DIR"

# Container engine
engine=""
if command -v docker >/dev/null 2>&1; then engine="docker"
elif command -v podman >/dev/null 2>&1; then engine="podman"
else
  echo "[ERR] Need docker or podman for cache install" >&2
  exit 127
fi

echo "[update_cache] Using image: $VEP_IMAGE"
"$engine" pull "$VEP_IMAGE" >/dev/null

# Run INSTALL.pl; mount cache+ref RW
echo "[update_cache] Running INSTALL.pl (this can take a while)"
"$engine" run --rm \
  -v "$CACHE_DIR":"$CACHE_DIR" \
  -v "$REF_DIR":"$REF_DIR" \
  -e "PERL5LIB=/opt/vep/.vep" \
  "$VEP_IMAGE" \
  perl INSTALL.pl $CACHE_OPTS --CACHE_DIR "$CACHE_DIR" --FASTA "$REF_DIR/${ASSEMBLY}.fa"

echo "[update_cache] Done."
