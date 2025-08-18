# shellcheck shell=bash
task_vep_cache_install() {
  require_cmd aria2c
  sudo mkdir -p "$CACHE_ROOT/tmp" "$CACHE_ROOT/homo_sapiens"
  local tar
  tar="$CACHE_ROOT/tmp/$(basename "$ENSEMBL_CACHE_URL")"

  say "Local vs remote size"
# shellcheck disable=SC2316
  local remote local
  remote=$(curl -sIL "$ENSEMBL_CACHE_URL" | awk -v IGNORECASE=1 '/^content-length:/ {print $2}' | tail -1 | tr -d '\r')
  local=$(stat -c %s "$tar" 2>/dev/null || echo 0)
  awk -v s="$local" -v t="$remote" 'BEGIN{ if(t>0) printf "Local %.2f GiB / Remote %.2f GiB (%.2f%%)\n", s/1024^3, t/1024^3, (s/t)*100; else print "Unknown remote size"; }'

  say "Fetch CHECKSUMS"
  ( cd "$CACHE_ROOT/tmp" && curl -sO "$(dirname "$ENSEMBL_CACHE_URL")/CHECKSUMS" )
  local expected
  expected=$(awk -v f="$(basename "$tar")" '$0 ~ f {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-Fa-f]{32}$/){print tolower($i); exit}}' "$CACHE_ROOT/tmp/CHECKSUMS" )
  [[ -n "$expected" ]] || { err "Could not parse MD5 EXPECTED."; exit 2; }

  say "Resume/Download if needed"
  if ! md5sum "$tar" 2>/dev/null | awk '{print $1}' | grep -qi "^$expected$"; then
    aria2c -c -x16 -s16 -k1M --timeout=60 --connect-timeout=20 --retry-wait=5 -m 0 \
           --auto-file-renaming=false --allow-overwrite=true --file-allocation=none \
           -d "$CACHE_ROOT/tmp" -o "$(basename "$tar")" "$ENSEMBL_CACHE_URL"
  else
    ok "Archive already matches expected MD5"
  fi

  say "Validate archive"
  gzip -t "$tar" || { err "gzip test failed"; exit 2; }
  md5sum "$tar" | awk '{print $1}' | grep -qi "^$expected$" || { err "MD5 mismatch after download"; exit 2; }
  tar -tzf "$tar" >/dev/null || { err "tar list failed"; exit 2; }

  say "Extract atomically"
  local tmp; tmp=$(mktemp -d)
  tar -xzf "$tar" -C "$tmp"
  sudo rsync -a --delete "$tmp/homo_sapiens/${VEP_RELEASE}_${VEP_ASM}/" "$CACHE_ROOT/homo_sapiens/${VEP_RELEASE}_${VEP_ASM}/"
  sudo rm -rf "$tmp"
  ok "VEP cache ready → $CACHE_ROOT/homo_sapiens/${VEP_RELEASE}_${VEP_ASM}"
}
register_task "vep-cache" "Download/verify/extract Ensembl VEP cache (resume+md5)" task_vep_cache_install "Downloads ~25GB to cache."
