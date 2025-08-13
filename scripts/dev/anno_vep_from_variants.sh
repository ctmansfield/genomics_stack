#!/usr/bin/env bash
set -euo pipefail

UPLOAD_ID="${1:-}"; [ -n "$UPLOAD_ID" ] || { echo "usage: anno_vep_from_variants.sh <upload_id>"; exit 2; }

ROOT=/root/genomics-stack
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

OUT="/mnt/nas_storage/genomics-stack/reports/upload_${UPLOAD_ID}/anno"
CACHE="/mnt/nas_storage/genomics-stack/vep_cache"
FASTA="$CACHE/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
IMG=ensemblorg/ensembl-vep
TAG=release_114.2
FASTA_IN_CONTAINER="/opt/vep/.vep/$(basename "$FASTA")"
VCF="$OUT/upload_${UPLOAD_ID}.fromvariants.in.vcf"
TSV="$OUT/upload_${UPLOAD_ID}.vep.tab.tsv"
CLEANED="$OUT/upload_${UPLOAD_ID}.vep.cleaned.tsv"

mkdir -p "$OUT"
[ -d "$CACHE" ] || { echo "VEP cache dir missing: $CACHE"; exit 4; }
[ -s "${FASTA}.fai" ] || samtools faidx "$FASTA"

# 1) Export a GRCh38 VCF directly from DB (join rsids -> variants on rsid)
{
  echo '##fileformat=VCFv4.2'
  echo '##reference=GRCh38'
  echo -e '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO'
  docker compose -f "$COMPOSE_FILE" exec -T db \
    psql -U genouser -d genomics -Atc "
      WITH rs AS (
        SELECT DISTINCT rsid
        FROM public.staging_array_calls
        WHERE upload_id=${UPLOAD_ID} AND rsid IS NOT NULL
      )
      SELECT
        CASE WHEN v.chrom ~ '^chr' THEN substring(v.chrom from 4) ELSE v.chrom END || E'\t' ||
        v.pos || E'\t' ||
        COALESCE(v.rsid,'rs0') || E'\t' ||
        v.ref || E'\t' ||
        v.alt || E'\t.\tPASS\t.'
      FROM rs
      JOIN public.variants v ON v.rsid = rs.rsid
      WHERE v.chrom IS NOT NULL AND v.pos IS NOT NULL AND v.ref IS NOT NULL AND v.alt IS NOT NULL
      ORDER BY v.chrom, v.pos
    "
} > "$VCF"

# Quick sanity: show data lines count
DLINES=$(grep -vc '^#' "$VCF" || true); echo "[vcf data lines] ${DLINES}"

# 2) VEP → TSV (tab output)
cat "$VCF" \
| docker run --rm -i -v "$CACHE":/opt/vep/.vep:ro "$IMG:$TAG" \
    vep --offline --cache --dir_cache /opt/vep/.vep \
        --species homo_sapiens --assembly GRCh38 \
        --fasta "$FASTA_IN_CONTAINER" \
        --input_file /dev/stdin \
        --tab --output_file /dev/stdout \
        --fields "Location,Allele,Gene,SYMBOL,Feature,Consequence,IMPACT,BIOTYPE,Existing_variation,CLIN_SIG,AF,gnomADg_AF,PolyPhen,SIFT,HGVSc,HGVSp" \
        --no_stats --force_overwrite --fork 4 --buffer_size 5000 \
> "$TSV"

# 3) Clean & import
grep -v '^[[:space:]]*#' "$TSV" \
| sed 's/\r$//' \
| awk -v id="$UPLOAD_ID" 'BEGIN{FS=OFS="\t"} NF{print id, $0}' \
> "$CLEANED"

echo "[cleaned rows] $(wc -l < "$CLEANED")"

if [ -s "$CLEANED" ]; then
  docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -v ON_ERROR_STOP=1 -c "
    CREATE SCHEMA IF NOT EXISTS anno;
    CREATE TABLE IF NOT EXISTS anno.vep_tsv (
      upload_id bigint, location text, allele text,
      gene text, symbol text, feature text, consequence text, impact text, biotype text,
      existing_variation text, clin_sig text, af text, gnomadg_af text,
      polyphen text, sift text, hgvsc text, hgvsp text
    );
    DELETE FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID};
    COPY anno.vep_tsv(upload_id,location,allele,gene,symbol,feature,consequence,impact,biotype,existing_variation,clin_sig,af,gnomadg_af,polyphen,sift,hgvsc,hgvsp)
    FROM STDIN WITH (FORMAT text, DELIMITER E'\t');" < "$CLEANED"
fi

docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics \
  -c "SELECT symbol, consequence, clin_sig FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID} ORDER BY symbol;"
