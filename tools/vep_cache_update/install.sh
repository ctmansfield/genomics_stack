#!/usr/bin/env bash
set -euo pipefail
CACHE_DIR="/mnt/nas_storage/vep/cache"
REF_DIR="/mnt/nas_storage/vep/reference"
ASSEMBLY="${ASSEMBLY:-GRCh38}"
mkdir -p "$CACHE_DIR" "$REF_DIR"
echo "[install] Updating VEP cache for ${ASSEMBLY}"
if [[ -x "/root/genomics-stack/tools/vep_cache_bootstrap_guard.sh" ]]; then
  /root/genomics-stack/tools/vep_cache_bootstrap_guard.sh pre
fi
# replace with your artifact fetch if needed
vep_install -a cf -s homo_sapiens -y "${ASSEMBLY}" --REFSEQ --CACHE_VERSION all \
  --CACHE_DIR "$CACHE_DIR" --FASTA "$REF_DIR/${ASSEMBLY}.fa"
if [[ -x "/root/genomics-stack/tools/vep_cache_bootstrap_guard.sh" ]]; then
  /root/genomics-stack/tools/vep_cache_bootstrap_guard.sh post
fi
echo "[install] Done."
