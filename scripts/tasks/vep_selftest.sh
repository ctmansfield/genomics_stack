# shellcheck shell=bash
task_vep_selftest() {
  local out="$CACHE_ROOT/out"
  sudo mkdir -p "$out"; sudo chown -R 1000:1000 "$CACHE_ROOT"; sudo chmod -R u+rwX,go+rX "$CACHE_ROOT"
  printf "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n1\t123456\trsTest\tA\tG\t.\t.\t.\n" > "$CACHE_ROOT/test.vcf"
  say "VEP test run"
  docker run --rm -u 1000:1000 \
    -v "$CACHE_ROOT":/opt/vep/.vep:ro \
    -v "$out":/out \
    ensemblorg/ensembl-vep:latest \
    vep --offline --cache --assembly GRCh38 \
        --dir_cache /opt/vep/.vep \
        --fasta /opt/vep/.vep/Homo_sapiens.GRCh38.dna.primary_assembly.fa \
        -i /opt/vep/.vep/test.vcf -o /out/test_vep.vcf --vcf \
        --pick --symbol --af --max_af --everything \
        --stats_text --force_overwrite --fork 2
  ok "VEP output:"
  sed -n '1,20p' "$out/test_vep.vcf"
}
register_task "vep-selftest" "Run a tiny offline VEP to verify cache" task_vep_selftest
