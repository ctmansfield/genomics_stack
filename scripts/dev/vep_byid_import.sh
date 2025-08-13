#!/usr/bin/env bash
set -euo pipefail

UPLOAD_ID="${1:-}"
[ -n "$UPLOAD_ID" ] || { echo "usage: vep_byid_import.sh <upload_id>"; exit 2; }

ROOT=/root/genomics-stack
OUT="/mnt/nas_storage/genomics-stack/reports/upload_${UPLOAD_ID}/anno"
CACHE="/mnt/nas_storage/genomics-stack/vep_cache"
IMG_VEP=ensemblorg/ensembl-vep
TAG_VEP=release_114.2
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

# pick a VCF (prefer normalized -> lifted -> original)
for p in "$OUT/upload_${UPLOAD_ID}.hg38.norm.vcf" \
         "$OUT/upload_${UPLOAD_ID}.hg38.vcf" \
         "$OUT/upload_${UPLOAD_ID}.vep.in.vcf"; do
  if [ -s "$p" ]; then SRC_VCF="$p"; break; fi
done
[ -n "${SRC_VCF:-}" ] || { echo "no VCF found under $OUT"; exit 3; }
[ -d "$CACHE" ] || { echo "VEP cache dir missing: $CACHE"; exit 4; }

RSIDS="$OUT/upload_${UPLOAD_ID}.rsids.txt"
awk 'BEGIN{FS="\t"} /^[^#]/ && $3 ~ /^rs/ {print $3}' "$SRC_VCF" | sort -u > "$RSIDS"

# VEP by ID → TSV
cat "$RSIDS" | docker run --rm -i -v "$CACHE":/opt/vep/.vep:ro "$IMG_VEP:$TAG_VEP" \
  vep --offline --cache --dir_cache /opt/vep/.vep \
      --species homo_sapiens --assembly GRCh38 \
      --format id --tab --output_file /dev/stdout \
      --fields "Location,Allele,Gene,SYMBOL,Feature,Consequence,IMPACT,BIOTYPE,Existing_variation,CLIN_SIG,AF,gnomADg_AF,PolyPhen,SIFT,HGVSc,HGVSp" \
      --no_stats --force_overwrite \
  > "$OUT/upload_${UPLOAD_ID}.vep.byid.tsv"

# clean + prepend upload_id
CLEANED="$OUT/upload_${UPLOAD_ID}.vep.cleaned.tsv"
grep -v '^[[:space:]]*#' "$OUT/upload_${UPLOAD_ID}.vep.byid.tsv" \
  | sed 's/\r$//' \
  | awk -v id="$UPLOAD_ID" 'BEGIN{FS=OFS="\t"} NF{print id, $0}' \
  > "$CLEANED"

# import + sanity
if [ -s "$CLEANED" ]; then
  docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -v ON_ERROR_STOP=1 -c \
"DELETE FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID};
 COPY anno.vep_tsv(upload_id,location,allele,gene,symbol,feature,consequence,impact,biotype,existing_variation,clin_sig,af,gnomadg_af,polyphen,sift,hgvsc,hgvsp)
 FROM STDIN WITH (FORMAT text, DELIMITER E'\t');" < "$CLEANED"
fi

docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -c \
"SELECT symbol, consequence, clin_sig FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID} ORDER BY symbol;"
