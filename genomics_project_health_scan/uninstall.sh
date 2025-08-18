#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${TARGET_ROOT:-/root/genomics-stack/tools/health_scan}"

echo "[uninstall] Removing $TARGET_ROOT"
rm -rf "$TARGET_ROOT"
echo "[uninstall] Done."
