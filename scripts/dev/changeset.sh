#!/usr/bin/env bash
set -euo pipefail

# Minimal changeset workflow for this repo
ROOT=${ROOT:-/root/genomics-stack}
REPO_DIR=${REPO_DIR:-$ROOT}
CHANGES_DIR=${CHANGES_DIR:-$REPO_DIR/docs/changes}
DEFAULT_REMOTE=${REMOTE:-origin}
TEST_BRANCH=${TEST_BRANCH:-test}
MAIN_BRANCH=${MAIN_BRANCH:-main}

die(){ echo "[error] $*" >&2; exit 1; }
cd "$REPO_DIR"

usage(){
  cat <<USAGE
changeset.sh new <slug> [-m "summary"]
changeset.sh capture-incoming [slug]
changeset.sh commit <slug> -m "message"
changeset.sh push-test [branch]
changeset.sh release <slug>
USAGE
}

ts(){ date +%Y%m%d_%H%M%S; }

cmd=${1:-}; shift || true
[[ -n "$cmd" ]] || { usage; exit 2; }

case "$cmd" in
  new)
    slug=${1:-}; shift || true
    [[ -n "$slug" ]] || die "need a slug (e.g. report-top)"
    summary=""
    if [[ "${1:-}" == "-m" ]]; then shift; summary=${1:-}; shift || true; fi
    mkdir -p "$CHANGES_DIR"
    path="$CHANGES_DIR/$(ts)_${slug}.md"
    {
      echo "# $slug"
      echo "Date: $(date -Iseconds)"
      echo
      [[ -n "$summary" ]] && echo "Summary: $summary" || echo "Summary: "
      cat <<'TEMPLATE'

## What changed
- …

## Why
- …

## Files touched
- …

## Install / test steps
- …

## Rollback
- …

TEMPLATE
    } > "$path"
    echo "$path"
    ;;
  capture-incoming)
    slug=${1:-incoming}
    INCOMING=${INCOMING:-/mnt/nas_storage/incoming}
    [[ -d "$INCOMING" ]] || die "incoming dir not found: $INCOMING"
    dest="incoming/$(ts)_${slug}"
    mkdir -p "$dest"
    shopt -s nullglob
    files=("$INCOMING"/*)
    if (( ${#files[@]} == 0 )); then echo "[info] nothing in $INCOMING"; exit 0; fi
    for f in "${files[@]}"; do
      bn=$(basename "$f")
      mv -f "$f" "$dest/$bn"
      echo "[moved] $bn -> $dest/"
    done
    git add "$dest"
    echo "[ok] staged incoming files in $dest"
    ;;
  commit)
    slug=${1:-}; shift || true
    [[ -n "$slug" ]] || die "need slug to reference"
    [[ "${1:-}" == "-m" ]] || die "use -m \"message\""
    shift
    msg=${1:-}; shift || true
    ref=$(ls -1t "$CHANGES_DIR"/*"${slug}"*.md 2>/dev/null | head -n1 || true)
    [[ -n "$ref" ]] || die "no change note matching slug: $slug"
    git add -A
    git commit -m "changeset: ${slug} — ${msg}" -m "Ref: ${ref#$REPO_DIR/}"
    ;;
  push-test)
    branch=${1:-$TEST_BRANCH}
    # ensure test branch exists remote
    git fetch "$DEFAULT_REMOTE" >/dev/null 2>&1 || true
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
      echo "[info] local $branch exists"
    else
      echo "[info] creating $branch from $MAIN_BRANCH"
      git checkout -B "$branch" "$MAIN_BRANCH"
    fi
    # push current HEAD to test
    git push -u "$DEFAULT_REMOTE" "HEAD:$branch"
    echo "[ok] pushed to $DEFAULT_REMOTE/$branch"
    ;;
  release)
    slug=${1:-}; [[ -n "$slug" ]] || die "need slug"
    tag="rel-$(ts)-${slug}"
    git checkout "$MAIN_BRANCH"
    git pull "$DEFAULT_REMOTE" "$MAIN_BRANCH" || true
    # fast-forward main with test if needed (simple model)
    if git rev-parse --verify "$TEST_BRANCH" >/dev/null 2>&1; then
      git merge --ff-only "$TEST_BRANCH" || die "cannot fast-forward $MAIN_BRANCH from $TEST_BRANCH"
    fi
    git tag -a "$tag" -m "release: $slug"
    git push "$DEFAULT_REMOTE" "$MAIN_BRANCH"
    git push "$DEFAULT_REMOTE" "$tag"
    echo "[ok] released tag $tag"
    ;;
  *)
    usage; exit 2;;
esac
