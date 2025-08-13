#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-/root/genomics-stack}
SCRIPTS="$ROOT/scripts"

# Common helpers + env
. "$SCRIPTS/lib/common.sh"

# ---- simple registry ----
declare -A TASK_FN TASK_DESC TASK_HELP
TASK_ORDER=()

register_task() {
  local name="$1" desc="$2" fn="$3" help="${4:-}"
  TASK_FN["$name"]="$fn"
  TASK_DESC["$name"]="$desc"
  TASK_HELP["$name"]="$help"
  TASK_ORDER+=("$name")
}

run_task() {
  local name="${1:-}"; shift || true
  if [[ -z "${name:-}" ]]; then
    echo "Usage: $0 <task> [args]   (try: $0 list)" >&2; exit 1
  fi
  if [[ -z "${TASK_FN[$name]+x}" ]]; then
    echo "Unknown task: $name (try: $0 list)" >&2; exit 1
  fi
  "${TASK_FN[$name]}" "$@"
}

# ---- load all task files by sourcing (not executing) ----
shopt -s nullglob
for f in "$SCRIPTS/tasks/"*.sh; do
  # shellcheck disable=SC1090
  . "$f"
done
shopt -u nullglob

# ---- CLI / menu ----
case "${1:-menu}" in
  list)
    printf "%-22s  %s\n" "TASK" "DESCRIPTION"
    printf "%-22s  %s\n" "----" "-----------"
    for t in "${TASK_ORDER[@]}"; do
      printf "%-22s  %s\n" "$t" "${TASK_DESC[$t]}"
    done
    ;;
  menu)
    i=1
    for t in "${TASK_ORDER[@]}"; do printf "%2d) %-20s - %s\n" "$i" "$t" "${TASK_DESC[$t]}"; ((i++)); done
    read -rp "Choose number or type task name: " pick
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
      idx=$((pick-1)); task="${TASK_ORDER[$idx]:-}"
      [[ -n "$task" ]] || { echo "Invalid choice"; exit 1; }
      run_task "$task"
    else
      run_task "$pick"
    fi
    ;;
  *)
    run_task "$@"
    ;;
esac
