#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s expand_aliases || true

ROOT=${ROOT:-/root/genomics-stack}
ENV_FILE=${ENV_FILE:-$ROOT/.env}

# colors only if tty
if [[ -t 1 ]]; then
  BOLD=$(tput bold); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; RESET=""
fi

say(){ echo -e "${BLUE}$*${RESET}"; }
ok(){  echo -e "${GREEN}[ok]${RESET} $*"; }
warn(){echo -e "${YELLOW}[warn]${RESET} $*"; }
die(){ echo -e "${RED}[err]${RESET} $*" >&2; exit 1; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
require_file(){ [[ -s "$1" ]] || die "Missing file: $1"; }
require_readable(){ [[ -r "$1" ]] || die "Not readable: $1"; }
require_dir(){ [[ -d "$1" ]] || die "Missing dir: $1"; }

confirm_or_exit(){
  local msg=${1:-"Proceed"}; local def=${2:-N}
  read -rp "$msg [y/N]: " ans; ans=${ans:-$def}
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted"
}

alias dc="sudo docker compose -f $ROOT/compose.yml"

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
