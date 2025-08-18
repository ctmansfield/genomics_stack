#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${TARGET_ROOT:-/root/genomics-stack/tools/health_scan}"

echo "[verify] Checking installation at $TARGET_ROOT"

[[ -x "$TARGET_ROOT/tools/health_scan.sh" ]] || { echo "[verify][FAIL] health_scan.sh not found or not executable"; exit 1; }
[[ -f "$TARGET_ROOT/docs/README.md" ]] || { echo "[verify][FAIL] README.md missing"; exit 1; }
[[ -f "$TARGET_ROOT/docs/RELEASE_NOTES.md" ]] || { echo "[verify][FAIL] RELEASE_NOTES.md missing"; exit 1; }

echo "[verify][OK] Files present."
echo "[verify] Dry-run help:"
"$TARGET_ROOT/tools/health_scan.sh" --help || true
