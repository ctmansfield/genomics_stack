#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

# --- locate repo root from this file ---
_SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd -- "$_SCRIPT_DIR/../.." && pwd)}"
cd "$ROOT"

# --- load pretty helpers if available, else minimal fallbacks ---
if [[ -r "$ROOT/scripts/lib/common.sh" ]]; then
  # shellcheck disable=SC1091
  . "$ROOT/scripts/lib/common.sh"
else
  say(){ echo "[*] $*"; }
  ok(){ echo "[ok] $*"; }
  warn(){ echo "[warn] $*"; }
  die(){ echo "[err] $*" >&2; exit 1; }
fi

BACKUPS_DIR="${BACKUPS_DIR:-/mnt/nas_storage/genomics-stack/backups}"
DEFAULT_REMOTE="${DEFAULT_REMOTE:-origin}"

usage() {
  cat <<USAGE
gitctl: convenience wrapper for common git + backup/release operations

Usage: bash scripts/dev/gitctl.sh <command> [args]

Core:
  status                      Show branch, ahead/behind, changes summary
  save [-m MSG]               git add -A && git commit (MSG default: "save <timestamp>")
  push [REMOTE] [BRANCH]      Push current branch (defaults: origin, current branch)
  pull [REMOTE] [BRANCH]      Pull/rebase (defaults: origin, current branch)
  set-identity NAME EMAIL     Set user.name / user.email (repo-local)
  set-remote URL|PATH         Set 'origin' to URL or local path

Releases & backups (to ${BACKUPS_DIR}):
  release [-t TAG] [-m MSG] [--include-untracked] [-k N] [--dry-run]
                              Tag + archive repo snapshot to backups; keep newest N
  list-releases               List release archives newest-first
  verify-release FILE.tgz     sha256sum -c the archive
  backup [NAME]               Tar your working tree (incl. untracked) to backups

Rollbacks / restore (SAFE-first):
  worktree TAG DIR            Create a read-only worktree checkout at DIR for TAG
  checkout TAG                Checkout TAG in-place (detached)  (non-destructive)
  rollback REF                HARD reset current branch to REF  (DESTRUCTIVE, confirm)
  extract FILE.tgz DIR        Extract a release archive to DIR (no .git)

Meta:
  doctor                      Normalize LF endings on scripts; basic sanity checks
  help                        Show this help

Environment:
  BACKUPS_DIR                 Where releases/backups are stored (default: ${BACKUPS_DIR})
  DEFAULT_REMOTE              Default remote name (default: origin)

Examples:
  bash scripts/dev/gitctl.sh status
  bash scripts/dev/gitctl.sh save -m "fix: report-pdf flags"
  bash scripts/dev/gitctl.sh push
  bash scripts/dev/gitctl.sh release -m "checkpoint" -k 10
  bash scripts/dev/gitctl.sh worktree v0.1 /tmp/gstack_v0.1
USAGE
}

require_repo() {
  command -v git >/dev/null 2>&1 || die "git not installed"
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $ROOT"
}

now_utc() { date -u +%Y%m%d-%H%M%SZ; }

cmd_status() {
  require_repo
  local b ahead behind
  b="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  ahead="$(git rev-list --left-right --count '@{u}'...HEAD 2>/dev/null | awk '{print $2}' || echo 0)"
  behind="$(git rev-list --left-right --count '@{u}'...HEAD 2>/dev/null | awk '{print $1}' || echo 0)"
  say "branch: $b  (ahead:$ahead behind:$behind)"
  git status --porcelain=v1 -b
}

cmd_save() {
  require_repo
  local msg
  msg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message) msg="${2:-}"; shift;;
      *) die "unknown arg: $1";;
    esac
    shift
  done
  msg="${msg:-save $(now_utc)}"
  git add -A
  if git diff --cached --quiet; then
    warn "no staged changes; nothing to commit"
    return 0
  fi
  git commit -m "$msg"
  ok "committed: $msg"
}

cmd_push() {
  require_repo
  local remote
  remote="${1:-$DEFAULT_REMOTE}"
  local branch
  branch="${2:-$(git rev-parse --abbrev-ref HEAD)}"
  say "pushing $branch -> $remote"
  git push -u "$remote" "$branch"
}

cmd_pull() {
  require_repo
  local remote
  remote="${1:-$DEFAULT_REMOTE}"
  local branch
  branch="${2:-$(git rev-parse --abbrev-ref HEAD)}"
  say "pulling (rebase) $remote/$branch"
  git pull --rebase "$remote" "$branch"
}

cmd_set_identity() {
  require_repo
  local name
  name="${1:-}"; local email="${2:-}"
  [[ -n "$name" && -n "$email" ]] || die "Usage: set-identity NAME EMAIL"
  git config user.name  "$name"
  git config user.email "$email"
  ok "set repo identity: $name <$email>"
}

cmd_set_remote() {
  require_repo
  local url
  url="${1:-}"; [[ -n "$url" ]]
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$url"
  else
    git remote add origin "$url"
  fi
  ok "origin -> $url"
}

# ---------- release / backup helpers ----------
mk_release_archive() {
  # args: TAG MSG INCLUDE_UNTRACKED(0/1) DRY(0/1) KEEP(optional)
  local tag
  tag="$1" msg="$2" include_untracked="$3" dry="$4" keep="${5:-}"
  mkdir -p "$BACKUPS_DIR"
  local branch shortsha ts out
  branch="$(git rev-parse --abbrev-ref HEAD || echo detached)"
  shortsha="$(git rev-parse --short HEAD)"
  ts="$(now_utc)"

  if [[ -z "$tag" ]]; then tag="rel-${ts}"; fi
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tag="${tag}-${shortsha}"
  fi
  local tagmsg
  tagmsg="${msg:-"release $tag on $branch@$shortsha"}"

  if [[ "$dry" -eq 0 ]]; then
    git tag -a "$tag" -m "$tagmsg"
    ok "created tag: $tag"
  else
    warn "[dry-run] would tag: $tag"
  fi

  local staging; staging="$(mktemp -d)"; trap 'rm -rf "$staging"' RETURN
  if [[ "$include_untracked" -eq 1 ]]; then
    command -v rsync >/dev/null 2>&1 || die "rsync required for --include-untracked"
    git ls-files -oi --directory --exclude-standard > "$staging/.exclude" || true
    rsync -a --delete --exclude '.git' --exclude-from "$staging/.exclude" "$ROOT/" "$staging/"
  else
    git archive --format=tar HEAD | tar -xf - -C "$staging"
  fi

  cat > "$staging/MANIFEST.json" <<EOF
{
  "name": "genomics-stack",
  "tag": "$tag",
  "commit": "$(git rev-parse HEAD)",
  "shortsha": "$shortsha",
  "branch": "$branch",
  "timestamp_utc": "$ts",
  "remote_origin": "$(git config --get remote.origin.url || echo "")"
}
EOF

  out="${BACKUPS_DIR}/genomics-stack_${tag}_${shortsha}.tgz"
  if [[ "$dry" -eq 0 ]]; then
    tar -C "$staging" -czf "$out" .
    sha256sum "$out" > "${out}.sha256"
    ok "archive: $out"
    ok "sha256: ${out}.sha256"
  else
    warn "[dry-run] would write: $out (+ .sha256)"
  fi

  if [[ -n "${keep:-}" && "$dry" -eq 0 ]]; then
    mapfile -t files < <(ls -1t "$BACKUPS_DIR"/genomics-stack_*.tgz 2>/dev/null || true)
    if (( ${#files[@]} > keep )); then
      for ((i=keep; i<${#files[@]}; i++)); do
        say "pruning ${files[$i]}"
        rm -f "${files[$i]}" "${files[$i]}.sha256" 2>/dev/null || true
      done
    fi
  fi
}

cmd_release() {
  require_repo
  local tag
  tag="" msg="" keep="" include_untracked=0 dry=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--tag) tag="${2:-}"; shift;;
      -m|--message) msg="${2:-}"; shift;;
      -k|--keep) keep="${2:-}"; shift;;
      --include-untracked) include_untracked=1;;
      --dry-run) dry=1;;
      *) die "unknown arg: $1";;
    esac
    shift
  done
  mk_release_archive "$tag" "$msg" "$include_untracked" "$dry" "$keep"
}

cmd_list_releases() {
  ls -lt "${BACKUPS_DIR}"/genomics-stack_*.tgz 2>/dev/null || true
}

cmd_verify_release() {
  local file
  file="${1:-}"; [[ -n "$file" ]]
  sha256sum -c "${file}.sha256"
}

cmd_backup() {
  mkdir -p "$BACKUPS_DIR"
  local name
  name="${1:-backup-$(now_utc)}"
  local out
  out="${BACKUPS_DIR}/genomics-stack_${name}.tgz"
  tar --exclude='.git' -czf "$out" .
  sha256sum "$out" > "${out}.sha256"
  ok "backup: $out"
}

# ---------- restore / rollback ----------
ask_yes_no() {
  local p
  p="${1:-Are you sure? [y/N]}"; read -r -p "$p " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

cmd_worktree() {
  require_repo
  local tag
  tag="${1:-}"; local dir="${2:-}"
  [[ -n "$tag" && -n "$dir" ]] || die "Usage: worktree TAG DIR"
  mkdir -p "$dir"
  git worktree add --detach "$dir" "$tag"
  ok "worktree at $dir for $tag"
}

cmd_checkout() {
  require_repo
  local tag
  tag="${1:-}"; [[ -n "$tag" ]]
  git checkout --detach "$tag"
  ok "checked out $tag (detached)"
}

cmd_rollback() {
  require_repo
  local ref
  ref="${1:-}"; [[ -n "$ref" ]]
  warn "This will HARD reset current branch to $ref and discard uncommitted changes."
  if ask_yes_no "Proceed? [y/N]"; then
  local safety
  safety="safety-rollback-\$(now_utc)"
    git tag -a "$safety" -m "safety tag before rollback to $ref"
    git reset --hard "$ref"
    ok "reset to $ref (safety tag: $safety)"
  else
    warn "aborted."
  fi
}

cmd_extract() {
  local file
  file="${1:-}"; local dir="${2:-}"
  [[ -n "$file" && -n "$dir" ]] || die "Usage: extract FILE.tgz DIR"
  mkdir -p "$dir"
  tar -xzf "$file" -C "$dir"
  ok "extracted to $dir"
}

# ---------- meta ----------
cmd_doctor() {
  # normalize endings for common script paths & quick syntax check
  sed -i 's/\r$//' scripts/genomicsctl.sh scripts/lib/common.sh scripts/tasks/*.sh 2>/dev/null || true
  if command -v bash >/dev/null 2>&1; then
    bash -n scripts/genomicsctl.sh 2>/dev/null || true
    bash -n scripts/lib/common.sh 2>/dev/null || true
  fi
  ok "doctor: normalized line endings; basic checks done."
}

# ---------- dispatcher ----------
cmd="${1:-help}"; shift || true
case "$cmd" in
  help|-h|--help) usage;;
  status) cmd_status;;
  save) cmd_save "$@";;
  push) cmd_push "$@";;
  pull) cmd_pull "$@";;
  set-identity) cmd_set_identity "$@";;
  set-remote) cmd_set_remote "$@";;
  release) cmd_release "$@";;
  list-releases) cmd_list_releases;;
  verify-release) cmd_verify_release "$@";;
  backup) cmd_backup "$@";;
  worktree) cmd_worktree "$@";;
  checkout) cmd_checkout "$@";;
  rollback) cmd_rollback "$@";;
  extract) cmd_extract "$@";;
  doctor) cmd_doctor;;
  *) die "unknown command: $cmd (try: help)";;
esac
