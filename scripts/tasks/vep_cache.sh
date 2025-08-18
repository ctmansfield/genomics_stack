# shellcheck shell=bash
task_vep_cache() {
  require_cmd aria2c
  local ROOT="/mnt/nas_storage/genomics-stack/vep_cache"
  local TMP="$ROOT/tmp"
  local TAR="$TMP/homo_sapiens_vep_114_GRCh38.tar.gz"
  local URL='https://ftp.ensembl.org/pub/release-114/variation/indexed_vep_cache/homo_sapiens_vep_114_GRCh38.tar.gz'
  mkdir -p "$ROOT/homo_sapiens" "$TMP"

  say "Check remote size / local"
  local REMOTE LOCAL
  REMOTE=$(curl -sIL "$URL" | awk -v IGNORECASE=1 '/^content-length:/ {print $2}' | tail -1 | tr -d '\r')
  LOCAL=$(stat -c %s "$TAR" 2>/dev/null || echo 0)
  awk -v s="$LOCAL" -v t="$REMOTE" 'BEGIN{ if(t>0) printf "Local %.2f GiB / Remote %.2f GiB (%.2f%%)\n", s/1024^3, t/1024^3, (s/t)*100; else print "Unknown remote size"; }'

  say "Download (resume/idempotent)"
  aria2c -c -x16 -s16 -k1M --retry-wait=5 -m 0 --allow-overwrite=true \
         --auto-file-renaming=false --file-allocation=none \
         -d "$TMP" -o "$(basename "$TAR")" "$URL" || true

  say "Validate archive (gzip+tar)"
  gzip -t "$TAR" || { err "gzip test failed"; return 2; }
  tar -tzf "$TAR" >/dev/null || { err "tar list failed"; return 2; }
  ok "archive looks good"

  say "Extract to temp and sync"
  local t; t=$(mktemp -d)
  tar -xzf "$TAR" -C "$t"
  mkdir -p "$ROOT/homo_sapiens/114_GRCh38"
  rsync -a --delete "$t/homo_sapiens/114_GRCh38/" "$ROOT/homo_sapiens/114_GRCh38/"
  rm -rf "$t"
  ok "VEP cache extracted"

  say "Ensure FASTA present & indexed"
  if [[ -s "$ROOT/Homo_sapiens.GRCh38.dna.primary_assembly.fa" && -s "$ROOT/Homo_sapiens.GRCh38.dna.primary_assembly.fa.fai" ]]; then
    ok "FASTA + FAI already present"
  else
    if [[ -s "$ROOT/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz" ]]; then
      docker run --rm -v "$ROOT":/data staphb/samtools:1.20 bash -lc '
        set -e
        gunzip -c /data/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz > /data/Homo_sapiens.GRCh38.dna.primary_assembly.fa
        samtools faidx /data/Homo_sapiens.GRCh38.dna.primary_assembly.fa
      '
      ok "built FASTA index"
    else
      warn "No FASTA found in $ROOT – skip indexing. (You can drop one in and re-run.)"
    fi
  fi
  sudo chown -R 1000:1000 "$ROOT"; sudo chmod -R u+rwX,go+rX "$ROOT"
  ok "VEP cache ready at $ROOT/homo_sapiens/114_GRCh38"
}
register_task "vep-cache" "Fetch/verify/extract human VEP cache + build FASTA index" task_vep_cache "Downloads ~25 GiB; uses aria2c."
