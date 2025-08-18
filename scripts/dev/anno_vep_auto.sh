#!/usr/bin/env bash
set -euo pipefail

UPLOAD_ID="${1:-}"; [ -n "$UPLOAD_ID" ] || { echo "usage: anno_vep_auto.sh <upload_id>"; exit 2; }

ROOT=/root/genomics-stack
OUT="/mnt/nas_storage/genomics-stack/reports/upload_${UPLOAD_ID}/anno"
CACHE="/mnt/nas_storage/genomics-stack/vep_cache"
FASTA="$CACHE/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

SRC="$OUT/upload_${UPLOAD_ID}.hg38.vcf"; [ -s "$SRC" ] || SRC="$OUT/upload_${UPLOAD_ID}.vep.in.vcf"
LFT_HDR="$OUT/upload_${UPLOAD_ID}.hg38.withctg.vcf"
NORM="$OUT/upload_${UPLOAD_ID}.hg38.norm.vcf"
VEP_VCF="$OUT/upload_${UPLOAD_ID}.vep.out.vcf"
TSV="$OUT/upload_${UPLOAD_ID}.vep.fromvcf.tsv"
CLEANED="$OUT/upload_${UPLOAD_ID}.vep.cleaned.tsv"

IMG_BCF=staphb/bcftools:1.17
IMG_VEP=ensemblorg/ensembl-vep
TAG_VEP=release_114.2
FASTA_IN_CONTAINER="/opt/vep/.vep/$(basename "$FASTA")"

[ -s "$SRC" ] || { echo "no input VCF under $OUT"; exit 3; }
[ -d "$CACHE" ] || { echo "VEP cache dir missing: $CACHE"; exit 4; }
[ -s "${FASTA}.fai" ] || samtools faidx "$FASTA"
mkdir -p "$OUT"

# 1) add ##contig header lines from FASTA .fai
CTG="$OUT/add.contigs.hdr"
awk -v OFS="" '{print "##contig=<ID="$1",length="$2">"}' "${FASTA}.fai" > "$CTG"
docker run --rm -v "$OUT":/d -v "$CACHE":/r "$IMG_BCF" \
  bcftools annotate -h "/d/$(basename "$CTG")" -Ov \
  -o "/d/$(basename "$LFT_HDR")" "/d/$(basename "$SRC")"

# 2) normalize against GRCh38
docker run --rm -v "$OUT":/d -v "$CACHE":/r "$IMG_BCF" \
  bcftools norm -f "/r/$(basename "$FASTA")" -c x -Ov "/d/$(basename "$LFT_HDR")" > "$NORM"

# 3) VEP → VCF (CSQ in INFO)
cat "$NORM" | docker run --rm -i -v "$CACHE":/opt/vep/.vep:ro "$IMG_VEP:$TAG_VEP" \
  vep --offline --cache --dir_cache /opt/vep/.vep \
      --species homo_sapiens --assembly GRCh38 \
      --fasta "$FASTA_IN_CONTAINER" \
      --input_file /dev/stdin \
      --vcf --output_file /dev/stdout \
      --everything --no_stats --force_overwrite --fork 4 --buffer_size 5000 \
  > "$VEP_VCF"

# 4) Parse CSQ → TSV (portable awk: function at top-level)
awk -v OFS="\t" -v UP="$UPLOAD_ID" '
  function F(name,   i) { return (name in idx) ? v[idx[name]] : "" }
  BEGIN{ FS="\t"; have_hdr=0 }
  /^##INFO=<ID=CSQ/ {
    if (match($0,/Format: ([^">]+)/,m)) {
      n=split(m[1],H,"|"); for(i=1;i<=n;i++) idx[H[i]]=i; have_hdr=1
    }
    next
  }
  /^#/ { next }
  {
    info=$8; csq="";
    n=split(info,a,";"); for(i=1;i<=n;i++) if (a[i] ~ /^CSQ=/) { csq=substr(a[i],5); break }
    if (csq=="") next
    m=split(csq,e,",");
    for (j=1;j<=m;j++) {
      split(e[j],v,"|");
      print UP, F("Location"), F("Allele"), F("Gene"), F("SYMBOL"), F("Feature"),
            F("Consequence"), F("IMPACT"), F("BIOTYPE"), F("Existing_variation"),
            F("CLIN_SIG"), F("AF"), F("gnomADg_AF"), F("PolyPhen"), F("SIFT"),
            F("HGVSc"), F("HGVSp")
    }
  }
  END{ if (!have_hdr) { print "[error] CSQ header missing" > "/dev/stderr"; exit 2 } }
' "$VEP_VCF" > "$TSV"

# 5) import
cp -f "$TSV" "$CLEANED"
docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -v ON_ERROR_STOP=1 -c "
CREATE SCHEMA IF NOT EXISTS anno;
CREATE TABLE IF NOT EXISTS anno.vep_tsv (
  upload_id bigint, location text, allele text,
  gene text, symbol text, feature text, consequence text, impact text, biotype text,
  existing_variation text, clin_sig text, af text, gnomadg_af text, polyphen text, sift text, hgvsc text, hgvsp text
);
DELETE FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID};
COPY anno.vep_tsv(upload_id,location,allele,gene,symbol,feature,consequence,impact,biotype,existing_variation,clin_sig,af,gnomadg_af,polyphen,sift,hgvsc,hgvsp)
FROM STDIN WITH (FORMAT text, DELIMITER E'\t');" < "$CLEANED"

docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics \
  -c "SELECT symbol, consequence, clin_sig FROM anno.vep_tsv WHERE upload_id=${UPLOAD_ID} ORDER BY symbol;"
