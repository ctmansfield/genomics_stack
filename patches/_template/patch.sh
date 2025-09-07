#!/usr/bin/env bash
# shellcheck shell=bash

# Exposed env: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR

patch_install() {
  echo "[${PATCH_CODE}] install starting in $PATCH_DIR"
  # put your install steps here; example:
  # python3 "$REPO_ROOT/components/ingest/build_manifest.py" "$NAS_ROOT/data/samples_raw" || true
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify starting in $PATCH_DIR"
  # put your verify steps here; example:
  # python3 "$REPO_ROOT/components/dbduck/duckdb_cli.py" bootstrap
  echo "[${PATCH_CODE}] verify_ok"
}
