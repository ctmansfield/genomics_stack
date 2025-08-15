#!/usr/bin/env bash
set -euo pipefail
CACHE_DIR="/mnt/nas_storage/vep/cache"
REF_DIR="/mnt/nas_storage/vep/reference"
ASSEMBLY="${ASSEMBLY:-GRCh38}"
echo "[verify] Sanity check cache files..."
test -d "$CACHE_DIR" && test -d "$REF_DIR"
test -s "$REF_DIR/${ASSEMBLY}.fa" || { echo "Missing reference FASTA"; exit 1; }
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
cat > "$TMPDIR/canary.vcf" <<VCF
##fileformat=VCFv4.2
#CHROM  POS ID  REF ALT QUAL  FILTER  INFO
1  10000  .   A   G   .   .   .
VCF
sed -i 's/ \+/\t/g' "$TMPDIR/ccanary.vcf" 2>/dev/null || true
sed -i 's/ \+/\t/g' "$TMPDIR/canary.vcf"
OUT="$TMPDIR/out.tsv"
scripts/vep/vep_annotate.py --vcf "$TMPDIR/canary.vcf" --out-tsv "$OUT" --assembly "$ASSEMBLY" --forks 2 --chunk-size 1000
diff -q scripts/vep/columns_vep_annotated.tsv <(head -n1 "$OUT" | tr '\t' '\n') >/dev/null || {
  echo "[verify] Header mismatch"; exit 1; }
echo "[verify] OK"
