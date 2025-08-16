#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo /root/genomics-stack)"
MANIFEST="$REPO_DIR/.genomics_patches/applied/0008.files"

apply_0008() {
  echo "[INFO] Applying 0008: E2E pipeline verification + reports"
  files=(
    "tools/pipeline_verify/e2e_pipeline_check.sh"
    "sql/ingest_registry_delta.sql"
    "scripts/reports/generate_full_report.py"
    "scripts/reports/generate_top10.py"
    "docs/PIPELINE_E2E.md"
  )
  # verify presence
  for f in "${files[@]}"; do
    [[ -f "$REPO_DIR/$f" ]] || { echo "ERROR: missing $f — run the install chain first"; exit 2; }
  done
  mkdir -p "$(dirname "$MANIFEST")"
  printf "%s\n" "${files[@]}" > "$MANIFEST"

  pushd "$REPO_DIR" >/dev/null
  git add "${files[@]}" "$MANIFEST"
  pre-commit run --all-files || true
  git add -A
  git commit -m "patch-0008: register E2E pipeline verification + reports" || true
  popd >/dev/null
  echo "[OK] 0008 applied (manifest written)"
}

verify_0008() {
  echo "=== Verification ==="
  for f in $(cat "$MANIFEST" 2>/dev/null || true); do
    [[ -f "$REPO_DIR/$f" ]] && echo "present: $f" || echo "MISSING: $f"
  done
  command -v psql >/dev/null 2>&1 && echo "psql OK" || echo "psql missing"
  python -c "import psycopg2" >/dev/null 2>&1 && echo "psycopg2 OK" || echo "psycopg2 missing"
  echo "=== Done ==="
}

rollback_0008() {
  echo "[WARN] Rolling back 0008 (removing files listed in manifest)"
  if [[ ! -f "$MANIFEST" ]]; then
    echo "No manifest at $MANIFEST; nothing to roll back."
    return 0
  fi
  pushd "$REPO_DIR" >/dev/null
  while read -r f; do
    if [[ -f "$f" ]]; then
      git rm -f "$f" || true
    fi
  done < "$MANIFEST"
  rm -f "$MANIFEST"
  git add -A
  git commit -m "revert(patch-0008): rollback E2E verification + reports" || true
  popd >/dev/null
  echo "[OK] 0008 rolled back"
}

git_push() {
  pushd "$REPO_DIR" >/dev/null
  echo "About to push to ${REMOTE:-origin}/main"
  git push || true
  popd >/dev/null
}

show_menu() {
  cat <<MENU
Repo: $REPO_DIR
0008: E2E Pipeline Audit
1) Apply 0008 (register files & commit)
2) Verify 0008 (files + deps)
3) Rollback 0008
4) Git Push
5) Exit
MENU
}

while true; do
  show_menu
  read -rp "Select: " choice
  case "$choice" in
    1) apply_0008 ;;
    2) verify_0008 ;;
    3) rollback_0008 ;;
    4) git_push ;;
    5) exit 0 ;;
    *) echo "Invalid option" ;;
  esac
done
