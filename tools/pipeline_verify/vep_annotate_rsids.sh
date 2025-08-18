#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve repo dir even if invoked via absolute path
if [[ -n "${BASH_SOURCE:-}" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
  REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
else
  REPO_DIR="${REPO_DIR:-/root/genomics-stack}"
fi
TMP_DIR="$REPO_DIR/tmp"; mkdir -p "$TMP_DIR"

# Load/export DSN if present; else default to local docker on 55432
if [[ -z "${PG_DSN:-}" && -f "$REPO_DIR/env.d/pg.env" ]]; then set -a; source "$REPO_DIR/env.d/pg.env"; set +a; fi
: "${PG_DSN:=host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics}"

# Defaults
UPLOAD_ID=""
ASSEMBLY="${ASSEMBLY:-GRCh38}"
VEP_IMAGE="${VEP_IMAGE:-ensemblorg/ensembl-vep:release_111}"
VEP_CACHE="${VEP_CACHE:-}"   # e.g. /mnt/nas_storage/vep_cache  or  $REPO_DIR/.vep_cache

usage(){ echo "Usage: $0 --file-id ID [--assembly GRCh38|GRCh37] [--cache-dir /path/.vep] [--image repo/image:tag]"; }

# Args
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

# Export RSIDs to a flat file
RSIDS="$TMP_DIR/rsids_${UPLOAD_ID}.txt"
psql "$PG_DSN" -Atqc "
  copy (
    select distinct rsid
    from variants
    where file_id = '$UPLOAD_ID'
      and rsid is not null and rsid <> ''
    order by rsid
  ) to stdout
" > "$RSIDS"

# Pick a cache dir automatically if not provided
if [[ -z "$VEP_CACHE" ]]; then
  for c in "$REPO_DIR/.vep_cache" "/mnt/nas_storage/vep_cache" "$HOME/.vep"; do
    [[ -d "$c" ]] && VEP_CACHE="$c" && break
  done
fi

# Validate cache structure for species/assembly
USE_OFFLINE=0
if [[ -n "$VEP_CACHE" && -d "$VEP_CACHE/homo_sapiens/$ASSEMBLY" ]]; then
  USE_OFFLINE=1
fi

# Use an existing local image only (no pulls)
if ! docker image inspect "$VEP_IMAGE" >/dev/null 2>&1; then
  echo "❌ VEP image '$VEP_IMAGE' is not present locally. Load it (docker load) or pre-pull once, then rerun."
  exit 3
fi

OUT_TSV="$TMP_DIR/vep_${UPLOAD_ID}.tsv"
if [[ "$USE_OFFLINE" -eq 1 ]]; then
  echo "[vep] using offline cache: $VEP_CACHE  assembly: $ASSEMBLY"
  docker run --rm \
    -v "$TMP_DIR":/work \
    -v "$VEP_CACHE":/opt/vep/.vep \
    "$VEP_IMAGE" \
    vep --offline --cache --dir_cache /opt/vep/.vep \
        --species homo_sapiens --assembly "$ASSEMBLY" \
        --format id --input_file /work/rsids_${UPLOAD_ID}.txt \
        --output_file /work/vep_${UPLOAD_ID}.tsv \
        --tab --fields "Uploaded_variation,SYMBOL,Consequence" \
        --force_overwrite --no_stats
else
  echo "⚠️  No usable cache found; using database mode with existing image (no pulls)."
  docker run --rm \
    -v "$TMP_DIR":/work \
    "$VEP_IMAGE" \
    vep --database \
        --species homo_sapiens --assembly "$ASSEMBLY" \
        --format id --input_file /work/rsids_${UPLOAD_ID}.txt \
        --output_file /work/vep_${UPLOAD_ID}.tsv \
        --tab --fields "Uploaded_variation,SYMBOL,Consequence" \
        --force_overwrite --no_stats
fi

# Load results into vep_annotations
psql "$PG_DSN" -v fid="$UPLOAD_ID" -v vfile="$OUT_TSV" <<'SQL'
\set ON_ERROR_STOP on
create table if not exists vep_annotations (
  file_id text, variant_id text, gene text, consequence text, priority_score numeric,
  primary key (file_id, variant_id)
);
create temp table tmp_vep(uploaded_variation text, symbol text, consequence text);
\copy tmp_vep from :'vfile' with (format csv, delimiter E'\t', header true, null '');
insert into vep_annotations(file_id, variant_id, gene, consequence, priority_score)
select :'fid'::text, uploaded_variation, nullif(symbol,''), nullif(consequence,''), null
from tmp_vep
where uploaded_variation <> '';
SQL

echo "[vep] annotated $(psql "$PG_DSN" -Atqc "select count(*) from vep_annotations where file_id='${UPLOAD_ID}';") rows for file_id=${UPLOAD_ID}"
