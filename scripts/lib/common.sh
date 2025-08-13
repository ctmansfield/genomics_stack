#!/usr/bin/env bash
set -Eeuo pipefail

# Derive repo root robustly from this file's location (…/scripts/lib/common.sh)
_COMMON_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd -- "$_COMMON_DIR/../.." && pwd)}"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

# Colors (safe under set -u)
if [[ -t 1 ]]; then
  : "${RED:=$'\e[31m'}"  ; : "${GREEN:=$'\e[32m'}"
  : "${YELLOW:=$'\e[33m'}"; : "${BLUE:=$'\e[34m'}"
  : "${BOLD:=$'\e[1m'}"  ; : "${RESET:=$'\e[0m'}"
else
  : "${RED:=}"   ; : "${GREEN:=}"
  : "${YELLOW:=}"; : "${BLUE:=}"
  : "${BOLD:=}"  ; : "${RESET:=}"
fi

say(){  echo -e "${BLUE-}$*${RESET-}"; }
ok(){   echo -e "${GREEN-}[ok]${RESET-} $*"; }
warn(){ echo -e "${YELLOW-}[warn]${RESET-} $*"; }
die(){  echo -e "${RED-}[err]${RESET-} $*" >&2; exit 1; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
require_readable(){ [[ -r "$1" ]] || die "Not readable: $1"; }

load_env(){
  set -a
  [[ -f "$ENV_FILE" ]] && . "$ENV_FILE"
  PGHOST=${PGHOST:-localhost}
  PGPORT=${PGPORT:-5433}
  PGUSER=${PGUSER:-genouser}
  PGDB=${PGDB:-genomics}
  BACKUP_DIR=${BACKUP_DIR:-/mnt/nas_storage/genomics-stack/backups}
  UPLOADS_DIR=${UPLOADS_DIR:-/mnt/nas_storage/genomics-stack/uploads}
  CACHE_ROOT=${CACHE_ROOT:-/mnt/nas_storage/genomics-stack/vep_cache}
  REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}
  set +a
}
