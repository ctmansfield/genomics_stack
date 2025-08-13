#!/usr/bin/env bash
set -euo pipefail

INCOMING="${INCOMING:-/mnt/nas_storage/incoming}"
ROOT="${ROOT:-/root/genomics-stack}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$INCOMING/_processed}"
FAILED_DIR="${FAILED_DIR:-$INCOMING/_failed}"
LOG="${LOG:-/var/log/genomics-incoming.log}"
DRY="${DRY:-0}"   # 1 = echo only
PATTERN="${PATTERN:-*}"  # e.g. PATTERN='*.patch'
PG_SVC="${PG_SVC:-db}"
PGUSER="${PGUSER:-genouser}"
PGDB="${PGDB:-genomics}"

COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"
mkdir -p "$ARCHIVE_DIR" "$FAILED_DIR"
touch "$LOG"

say(){ printf '[%s] %s\n' "$(date +%F %T)" "$*" | tee -a "$LOG" ; }
run(){ if [ "$DRY" = "1" ]; then say "(dry) $*"; else "$@"; fi; }

[ -d "$ROOT/.git" ] || { say "ERROR: not a git repo: $ROOT"; exit 2; }

apply_patch(){
  local f="$1"
  say "apply patch: $f"
  ( cd "$ROOT"
    if git am --signoff < "$f"; then
      say "git am ok"
    else
      say "git am failed, trying git apply --3way"
      git am --abort || true
      git apply --3way "$f"
      git add -A
      git commit -m "incoming: apply patch $(basename "$f")"
    fi
  )
}

apply_bundle(){
  local f="$1"
  say "apply bundle: $f"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  case "$f" in
    *.tar.gz|*.tgz) tar -C "$tmp" -xzf "$f" ;;
    *.zip) unzip -q "$f" -d "$tmp" ;;
    *) say "unknown archive: $f"; return 1 ;;
  esac
  rsync -a --exclude '.git/' --exclude 'db_data/' --exclude 'metabase_data/' "$tmp"/ "$ROOT"/
  ( cd "$ROOT"; git add -A; git commit -m "incoming: sync bundle $(basename "$f")" )
  # optional post-install
  if [ -x "$ROOT/install.sh" ]; then ( cd "$ROOT"; ./install.sh ); fi
}

apply_sql(){
  local f="$1"
  say "apply SQL: $f"
  run docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" \
      psql -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 < "$f"
}

run_script(){
  local f="$1"
  say "run script: $f"
  run bash "$f"
}

stage_doc(){
  local f="$1"
  say "stage doc: $f"
  mkdir -p "$ROOT/docs/incoming"
  cp -f "$f" "$ROOT/docs/incoming/"
  ( cd "$ROOT"; git add "docs/incoming/$(basename "$f")"; git commit -m "incoming: doc $(basename "$f")" )
}

process_one(){
  local f="$1"
  case "$f" in
    *.patch|*.diff) apply_patch "$f" ;;
    *.tar.gz|*.tgz|*.zip) apply_bundle "$f" ;;
    *.sql) apply_sql "$f" ;;
    *.sh) chmod +x "$f"; run_script "$f" ;;
    *.md|*.txt) stage_doc "$f" ;;
    *) say "skip (unknown type): $f"; return 2 ;;
  esac
}

archive_ok(){ local f="$1"; ts="$(date +%Y%m%d_%H%M%S)"; mv -f "$f" "$ARCHIVE_DIR/$(basename "$f").$ts"; }
archive_fail(){ local f="$1"; ts="$(date +%Y%m%d_%H%M%S)"; mv -f "$f" "$FAILED_DIR/$(basename "$f").$ts"; }

# Lock to avoid concurrent runs
lockfile="/var/lock/genomics-incoming.lock"
exec 9>"$lockfile"
flock -n 9 || { say "another process_incoming is running"; exit 0; }

shopt -s nullglob
files=( "$INCOMING"/$PATTERN )
if [ ${#files[@]} -eq 0 ]; then say "no files in $INCOMING matching $PATTERN"; exit 0; fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  say "== processing $(basename "$f") =="
  if process_one "$f"; then
    say "OK: $(basename "$f")"
    [ "$DRY" = "1" ] || archive_ok "$f"
  else
    say "FAIL: $(basename "$f")"
    [ "$DRY" = "1" ] || archive_fail "$f"
  fi
done
say "done."
