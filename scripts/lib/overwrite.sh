#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FORCE="${FORCE:-0}"

_confirm() {
  if [ "$FORCE" = "1" ]; then return 0; fi
  read -r -p "[?] Overwrite $1 ? [y/N] " ans
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

_backup_target() {
  local target="$1"
  [ -e "$target" ] || return 0
  sudo mkdir -p "$BACKUP_DIR"
  local base ts tarfile
  base="$(basename "$target")"
  ts="$(date +%Y%m%d_%H%M%S)"
  tarfile="$BACKUP_DIR/backup_${base}_${ts}.tgz"
  sudo tar -C / -czf "$tarfile" "${target#/}"
  ok "Backup -> $tarfile"
}

# owrite <path>  (content from stdin -> tmp -> atomically install)
owrite() {
  local target="$1"; shift || true
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"

  sudo mkdir -p "$(dirname "$target")"

  if [ -e "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    ok "Unchanged: $target"
    return 0
  fi

  if [ -e "$target" ]; then
    _confirm "$target" || { warn "Skipped: $target"; rm -f "$tmp"; return 0; }
    _backup_target "$target"
  fi

  sudo install -m 0644 "$tmp" "$target"
  rm -f "$tmp"
  ok "Wrote: $target"
}
