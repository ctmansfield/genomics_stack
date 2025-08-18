#!/usr/bin/env bash
set -euo pipefail

# Default install root
TARGET_ROOT="${TARGET_ROOT:-/root/genomics-stack/tools/health_scan}"

echo "[install] Installing genomics project health scan to: $TARGET_ROOT"

mkdir -p "$TARGET_ROOT"
cp -av tools "$TARGET_ROOT/"
install -m 0755 tools/health_scan.sh "$TARGET_ROOT/tools/health_scan.sh"

# Copy docs
mkdir -p "$TARGET_ROOT/docs"
cp -av README.md RELEASE_NOTES.md "$TARGET_ROOT/docs/"

echo "[install] Done."
echo "[install] You can now run: $TARGET_ROOT/tools/health_scan.sh --help"
