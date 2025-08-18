# shellcheck shell=bash
# Global settings
STACK_DIR=/root/genomics-stack
COMPOSE_FILE="$STACK_DIR/compose.yml"
UPLOADS=/mnt/nas_storage/genomics-stack/uploads
BACKUP_DIR=/mnt/nas_storage/genomics-stack/backups
CACHE_ROOT=/mnt/nas_storage/genomics-stack/vep_cache
DB_HOST=localhost
DB_PORT=5433
EDITOR=${EDITOR:-vi}

# Pull core creds from .env if present
if [[ -f "$STACK_DIR/.env" ]]; then
  export $(grep -E '^(POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_DB|UPLOAD_TOKEN)=' "$STACK_DIR/.env" | xargs -d '\n' -I{} echo {})
fi
PGUSER="${POSTGRES_USER:-genouser}"
PGPASS="${POSTGRES_PASSWORD:-}"
PGDB="${POSTGRES_DB:-genomics}"

# ---- Installer defaults (safe to tweak) ----
VEP_RELEASE=${VEP_RELEASE:-114}
VEP_ASM=${VEP_ASM:-GRCh38}
CACHE_ROOT=${CACHE_ROOT:-/mnt/nas_storage/genomics-stack/vep_cache}
UPLOADS=${UPLOADS:-/mnt/nas_storage/genomics-stack/uploads}
BACKUP_DIR=${BACKUP_DIR:-/mnt/nas_storage/genomics-stack/backups}

ENSEMBL_CACHE_URL=${ENSEMBL_CACHE_URL:-https://ftp.ensembl.org/pub/release-${VEP_RELEASE}/variation/indexed_vep_cache/homo_sapiens_vep_${VEP_RELEASE}_${VEP_ASM}.tar.gz}
FASTA_URL=${FASTA_URL:-https://ftp.ensembl.org/pub/release-${VEP_RELEASE}/fasta/homo_sapiens/dna/Homo_sapiens.${VEP_ASM}.dna.primary_assembly.fa.gz}

# Compose defaults (idempotent writer uses these if .env missing)
POSTGRES_USER=${POSTGRES_USER:-genouser}
POSTGRES_DB=${POSTGRES_DB:-genomics}
# POSTGRES_PASSWORD: created if missing
HASURA_GRAPHQL_ADMIN_SECRET=${HASURA_GRAPHQL_ADMIN_SECRET:-}
HASURA_GRAPHQL_JWT_SECRET=${HASURA_GRAPHQL_JWT_SECRET:-}
