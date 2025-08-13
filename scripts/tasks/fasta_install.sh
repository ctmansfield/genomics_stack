task_fasta_install() {
  sudo mkdir -p "$CACHE_ROOT"
  local gz="$CACHE_ROOT/$(basename "$FASTA_URL")"
  say "Download FASTA (resume)"
  aria2c -c -x8 -s8 -k1M -d "$CACHE_ROOT" -o "$(basename "$gz")" "$FASTA_URL"

  say "Decompress + faidx (samtools 1.20 in container)"
  docker pull staphb/samtools:1.20 >/dev/null
  docker run --rm -v "$CACHE_ROOT":/data staphb/samtools:1.20 bash -lc '
    set -e
    if [ ! -s /data/'"$(basename "$gz" .gz)"' ]; then
      gunzip -c /data/'"$(basename "$gz")"' > /data/'"$(basename "$gz" .gz)"'
    fi
    samtools faidx /data/'"$(basename "$gz" .gz)"'
  '
  ok "FASTA + .fai ready → $CACHE_ROOT"
}
register_task "fasta" "Download GRCh38 primary FASTA + build .fai" task_fasta_install "Writes ~3GB decompressed FASTA."
