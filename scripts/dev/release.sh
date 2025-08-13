#!/usr/bin/env bash
set -euo pipefail

# --- locate repo root from this file ---
_SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$_SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

BACKUPS_DIR="${BACKUPS_DIR:-/mnt/nas_storage/genomics-stack/backups}"

usage() {
  cat <<USAGE
Usage: bash scripts/dev/release.sh [options]

Options:
  -t, --tag TAG         Tag name to use (default: rel-YYYYmmdd-HHMMSSZ)
  -m, --message MSG     Tag message (default: "release <tag> on <branch>@<sha>")
  -f, --force           Allow dirty working tree (otherwise requires clean)
  -k, --keep N          Retain only the newest N archives (delete older)
      --include-untracked  Include untracked, non-ignored files (needs rsync)
      --dry-run         Show what would happen but do not tag/write files
  -h, --help            Show this help

Artifacts:
  ${BACKUPS_DIR}/genomics-stack_<tag>_<shortsha>.tgz
  ${BACKUPS_DIR}/genomics-stack_<tag>_<shortsha>.tgz.sha256
USAGE
}

# --- parse args ---
force=0; tag=""; msg=""; keep=""; include_untracked=0; dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag) tag="${2:-}"; shift;;
    -m|--message) msg="${2:-}"; shift;;
    -f|--force) force=1;;
    -k|--keep) keep="${2:-}"; shift;;
    --include-untracked) include_untracked=1;;
    --dry-run) dry=1;;
    -h|--help) usage; exit 0;;
    *) echo "[err] unknown option: $1" >&2; usage; exit 1;;
  esac
  shift
done

# --- sanity checks ---
command -v git >/dev/null 2>&1 || { echo "[err] git required"; exit 1; }
mkdir -p "$BACKUPS_DIR"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "[err] not a git repo: $ROOT" >&2; exit 1; }
git rev-parse --verify -q HEAD >/dev/null || { echo "[err] repo has no commits"; exit 1; }

if [[ $force -eq 0 ]]; then
  git diff --quiet || { echo "[err] uncommitted changes (use -f to override)"; exit 1; }
  git diff --cached --quiet || { echo "[err] staged but uncommitted changes (use -f)"; exit 1; }
fi

branch="$(git rev-parse --abbrev-ref HEAD || echo 'detached')"
shortsha="$(git rev-parse --short HEAD)"
timestamp="$(date -u +%Y%m%d-%H%M%SZ)"

# derive tag if not provided
if [[ -z "$tag" ]]; then
  tag="rel-${timestamp}"
fi

# if tag exists, disambiguate
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  tag="${tag}-${shortsha}"
fi

tagmsg="${msg:-"release $tag on $branch@$shortsha"}"

# --- create tag (annotated) ---
if [[ $dry -eq 0 ]]; then
  git tag -a "$tag" -m "$tagmsg"
  echo "[ok] created tag: $tag"
else
  echo "[dry] would create tag: $tag"
fi

# --- stage content into temp dir ---
staging="$(mktemp -d)"; trap 'rm -rf "$staging"' EXIT

if [[ $include_untracked -eq 1 ]]; then
  command -v rsync >/dev/null 2>&1 || { echo "[err] rsync required for --include-untracked"; exit 1; }
  git ls-files -oi --directory --exclude-standard > "$staging/.exclude" || true
  rsync -a --delete \
    --exclude '.git' \
    --exclude-from "$staging/.exclude" \
    "$ROOT/" "$staging/"
else
  # tracked files at HEAD
  git archive --format=tar HEAD | tar -xf - -C "$staging"
fi

# --- embed manifest ---
cat > "$staging/MANIFEST.json" <<EOF
{
  "name": "genomics-stack",
  "tag": "$tag",
  "commit": "$(git rev-parse HEAD)",
  "shortsha": "$shortsha",
  "branch": "$branch",
  "timestamp_utc": "$timestamp",
  "remote_origin": "$(git config --get remote.origin.url || echo "")"
}
EOF

# --- package + checksum ---
out="${BACKUPS_DIR}/genomics-stack_${tag}_${shortsha}.tgz"
if [[ $dry -eq 0 ]]; then
  tar -C "$staging" -czf "$out" .
  sha256sum "$out" > "${out}.sha256"
  echo "[ok] archive: $out"
  echo "[ok] sha256: ${out}.sha256"
else
  echo "[dry] would write: $out and ${out}.sha256"
fi

# --- retention (keep newest N) ---
if [[ -n "${keep:-}" && $dry -eq 0 ]]; then
  mapfile -t files < <(ls -1t "$BACKUPS_DIR"/genomics-stack_*.tgz 2>/dev/null || true)
  if (( ${#files[@]} > keep )); then
    for ((i=keep; i<${#files[@]}; i++)); do
      echo "[info] pruning ${files[$i]}"
      rm -f "${files[$i]}" "${files[$i]}.sha256" 2>/dev/null || true
    done
  fi
fi
