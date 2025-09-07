# shellcheck shell=bash

# Map: CODE -> directory name
declare -A PATCH_DIRS=(
  [B7]="patch_B7_dbduck_bootstrap"
  [B8]="patch_B8_dbduck_hydrators"
  [A7]="patch_A7_ingest_norm"
  [D4]="patch_D4_orch_snakemake"
  [B10]="patch_B10_dbduck_views"
)

# Recommended run order (topological-ish). You can adjust as you add patches.
PATCH_ORDER=( B7 A7 B8 D4 B10 )

# Optional dependencies (space-separated codes)
declare -A PATCH_DEPS=(
  [B8]="B7"
  [D4]="A7 B7"
  [B10]="B7"
)

# Helper to resolve a code to its absolute directory
patch_dir() {
  local code="$1"
  local dir="${PATCH_DIRS[$code]}"
  [[ -z "$dir" ]] && { echo "ERR: unknown patch code: $code" >&2; return 2; }
  # Prefer repo-local path
  if [[ -n "${REPO_ROOT:-}" && -d "$REPO_ROOT/$dir" ]]; then
    printf "%s/%s\n" "$REPO_ROOT" "$dir"
  else
    printf "%s\n" "$dir"
  fi
}
