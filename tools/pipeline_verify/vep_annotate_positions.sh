#!/usr/bin/env bash
set -Eeuo pipefail

SELF_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
TMP_DIR="$REPO_DIR/tmp"; mkdir -p "$TMP_DIR"

if [[ -z "${PG_DSN:-}" && -f "$REPO_DIR/env.d/pg.env" ]]; then
  set -a; source "$REPO_DIR/env.d/pg.env"; set +a
fi
: "${PG_DSN:=host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics}"

UPLOAD_ID=""
ASSEMBLY="${ASSEMBLY:-GRCh38}"
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_114.2}"
VEP_CACHE="${VEP_CACHE:-}"

usage(){ echo "Usage: $0 --file-id ID [--assembly GRCh38|GRCh37] [--cache-dir /path/.vep] [--image repo/image:tag]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-id) UPLOAD_ID="$2"; shift 2;;
    --assembly) ASSEMBLY="$2"; shift 2;;
    --cache-dir) VEP_CACHE="$2"; shift 2;;
    --image) VEP_IMAGE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done
[[ -n "$UPLOAD_ID" ]] || { echo "Missing --file-id"; exit 2; }

# Find cache
if [[ -z "$VEP_CACHE" ]]; then
  for c in /mnt/nas_storage/genomics-stack/vep_cache /mnt/nas_storage/vep_cache "$REPO_DIR/.vep" "$HOME/.vep" /data/vep /srv/vep_cache; do
    [[ -d "$c" ]] && VEP_CACHE="$c" && break
  done
fi
[[ -d "$VEP_CACHE" ]] || { echo "❌ cache dir not found: $VEP_CACHE"; exit 2; }
if compgen -G "$VEP_CACHE/homo_sapiens/*_GRCh38" >/dev/null && [[ ! -d "$VEP_CACHE/homo_sapiens/GRCh38" ]]; then
  ln -s "$(ls -d "$VEP_CACHE"/homo_sapiens/*_GRCh38 | head -n1)" "$VEP_CACHE/homo_sapiens/GRCh38" 2>/dev/null || true
fi

IN="$TMP_DIR/vep_input_${UPLOAD_ID}.txt"
OUT="$TMP_DIR/vep_${UPLOAD_ID}.tsv"
echo "[vep] building Ensembl-format input: $IN"

# NOTE: use shell interpolation for $UPLOAD_ID; also strip a leading 'chr' if present
psql "$PG_DSN" -AtF $'\t' -c "
COPY (
  SELECT
    regexp_replace(chrom, '^chr', '') AS chrom,
    pos AS start,
    pos AS end,
    CASE
      WHEN allele1 IS NOT NULL AND allele2 IS NOT NULL THEN allele1 || '/' || allele2
      WHEN allele1 IS NOT NULL THEN allele1 || '/N'
      ELSE 'N/N'
    END AS allele
  FROM variants
  WHERE file_id = '$UPLOAD_ID'
    AND regexp_replace(chrom, '^chr', '') ~ '^(?:[0-9]+|X|Y|MT|M)$'
) TO STDOUT
" > "$IN"

echo "[vep] using image: $VEP_IMAGE"
echo "[vep] using cache: $VEP_CACHE  assembly: $ASSEMBLY"

docker run --rm -u 0:0 \
  -v "$VEP_CACHE":/opt/vep/.vep \
  -v "$TMP_DIR":/work \
  -w /work \
  "$VEP_IMAGE" \
  vep --offline --cache \
      --species homo_sapiens --assembly "$ASSEMBLY" \
      --input_file "$(basename "$IN")" \
      --output_file "$(basename "$OUT")" \
      --tab \
      --fields "Location,Allele,SYMBOL,Consequence" \
      --force_overwrite --no_stats

echo "[vep] loading annotations into vep_annotations…"
psql "$PG_DSN" -v tsv="$OUT" -v u="$UPLOAD_ID" <<'SQL'
\set ON_ERROR_STOP on
CREATE TEMP TABLE vep_raw(location text, allele text, symbol text, consequence text);
\copy vep_raw FROM :'tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true);

WITH parsed AS (
  SELECT
    regexp_replace(split_part(location, ':', 1), '^chr', '') AS chrom,
    regexp_replace(split_part(location, ':', 2), '-.*$', '')::bigint AS pos,
    split_part(allele, '/', 1) AS a1,
    split_part(allele, '/', 2) AS a2,
    symbol, consequence
  FROM vep_raw
)
INSERT INTO vep_annotations(file_id, variant_id, gene, consequence, priority_score)
SELECT
  :'u'::text AS file_id,
  COALESCE(v.rsid, format('chr%s:%s:%s:%s', p.chrom, p.pos, p.a1, p.a2)) AS variant_id,
  p.symbol AS gene,
  p.consequence,
  NULL::numeric
FROM parsed p
LEFT JOIN variants v
  ON v.file_id = :'u'::text
 AND regexp_replace(v.chrom, '^chr', '') = p.chrom
 AND v.pos = p.pos
 AND (
      (v.allele1 = p.a1 AND v.allele2 = p.a2) OR
      (v.allele1 = p.a2 AND v.allele2 = p.a1)
     )
ON CONFLICT (file_id, variant_id) DO UPDATE
SET gene = EXCLUDED.gene,
    consequence = EXCLUDED.consequence;
SQL

echo "[vep] annotated $(psql "$PG_DSN" -Atqc "select count(*) from vep_annotations where file_id='${UPLOAD_ID}';") rows for file_id=${UPLOAD_ID}"
