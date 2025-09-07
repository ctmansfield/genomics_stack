#!/usr/bin/env bash
set -euo pipefail

# --- config & lib -------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$ROOT}"
ENV_FILE="$REPO_ROOT/.env"
LOG_ROOT="$REPO_ROOT/logs/patchctl"
mkdir -p "$LOG_ROOT"

# Load env (NAS_ROOT, DUCKDB_PATH, etc.)
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

# Basic sanity
: "${NAS_ROOT:?NAS_ROOT not set (from .env)}"
: "${DUCKDB_PATH:?DUCKDB_PATH not set (from .env)}"

# shellcheck disable=SC1091
source "$REPO_ROOT/patches/registry.sh"

_ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }
die() { echo "[$(_ts)] ERROR: $*" >&2; exit 1; }
info(){ echo "[$(_ts)] $*"; }

# --- core executor ------------------------------------------------------------
_run_stage() {
  local code="$1" stage="$2"
  local pdir; pdir="$(patch_dir "$code")"
  [[ -d "$pdir" ]] || die "patch dir not found for $code: $pdir"

  local log_dir="$LOG_ROOT/$code"
  mkdir -p "$log_dir"
  local log="$log_dir/${stage}_$(date +%Y%m%d_%H%M%S).log"

  info "[$code] stage=$stage dir=$pdir log=$log"

  # Prefer unified patch.sh with functions; else fall back to install.sh / verify.sh
  if [[ -f "$pdir/patch.sh" ]]; then
    # shellcheck disable=SC1090
    source "$pdir/patch.sh"
    case "$stage" in
      install) type patch_install >/dev/null 2>&1 || die "$code: patch_install() missing";;
      verify)  type patch_verify  >/dev/null 2>&1 || die "$code: patch_verify()  missing";;
      *) die "unknown stage: $stage";;
    esac

    ( export NAS_ROOT REPO_ROOT DUCKDB_PATH PATCH_CODE="$code" PATCH_DIR="$pdir"
      export PATH="$REPO_ROOT/.venv_gs2/bin:$PATH"
      set -x
      if [[ "$stage" == "install" ]]; then patch_install; else patch_verify; fi
    ) 2>&1 | tee "$log"

  else
    # Compatibility mode: existing install.sh / verify.sh
    local script="$pdir/$stage.sh"
    [[ -x "$script" ]] || die "missing executable $script"
    ( export NAS_ROOT REPO_ROOT DUCKDB_PATH PATCH_CODE="$code" PATCH_DIR="$pdir"
      export PATH="$REPO_ROOT/.venv_gs2/bin:$PATH"
      set -x
      bash "$script"
    ) 2>&1 | tee "$log"
  fi

  info "[$code] $stage_ok"
}

_run_with_deps() {
  # Run deps (install) then code (install+verify)
  local code="$1"
  local deps="${PATCH_DEPS[$code]:-}"
  for d in $deps; do
    _run_with_deps "$d"
  done
  # To avoid re-running a dep multiple times in same session, mark with a file in tmp
  local stamp="$LOG_ROOT/.ran_${code}_install"
  if [[ ! -f "$stamp" ]]; then
    _run_stage "$code" install
    touch "$stamp"
  fi
  _run_stage "$code" verify
}

list() {
  echo "Known patches (order): ${PATCH_ORDER[*]}"
  printf "Code\tDir\t\tDeps\n"
  for c in "${PATCH_ORDER[@]}"; do
    printf "%s\t%s\t%s\n" "$c" "${PATCH_DIRS[$c]}" "${PATCH_DEPS[$c]:-}"
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  list
  install <CODE>         # run only install for that patch
  verify  <CODE>         # run only verify  for that patch
  run     <CODE>         # run deps (install), then install+verify for CODE
  run --all              # run install+verify for all patches in order
  logs   <CODE>          # show latest logs for a patch

Examples:
  scripts/patchctl.sh list
  scripts/patchctl.sh run B7
  scripts/patchctl.sh run --all
  scripts/patchctl.sh logs B10
EOF
}

logs() {
  local code="$1"
  local ld="$LOG_ROOT/$code"
  [[ -d "$ld" ]] || die "no logs dir for $code"
  echo "== $code logs in: $ld =="
  ls -ltr "$ld" || true
}

# --- entry --------------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
  list) list ;;
  install) code="${1:-}"; [[ -n "$code" ]] || die "need CODE"; _run_stage "$code" install ;;
  verify)  code="${1:-}"; [[ -n "$code" ]] || die "need CODE"; _run_stage "$code" verify ;;
  run)
    if [[ "${1:-}" == "--all" ]]; then
      rm -f "$LOG_ROOT"/.ran_* || true
      for c in "${PATCH_ORDER[@]}"; do _run_with_deps "$c"; done
    else
      code="${1:-}"; [[ -n "$code" ]] || die "need CODE or --all"
      rm -f "$LOG_ROOT"/.ran_* || true
      _run_with_deps "$code"
    fi
    ;;
  logs) code="${1:-}"; [[ -n "$code" ]] || die "need CODE"; logs "$code" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
