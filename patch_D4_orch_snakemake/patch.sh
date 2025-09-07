#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# Exposed: NAS_ROOT, REPO_ROOT, DUCKDB_PATH, PATCH_CODE, PATCH_DIR

_snake() {
  # prefer venv python
  if command -v python >/dev/null 2>&1; then
    python -m snakemake -s "${REPO_ROOT}/components/orch/Snakefile" "$@"
  else
    snakemake -s "${REPO_ROOT}/components/orch/Snakefile" "$@"
  fi
}

patch_install() {
  echo "[${PATCH_CODE}] install: orchestrator check (+ optional noop)"
  # Nothing to install; the DAG lives in components/orch/Snakefile.
  # Ensure dirs exist so ingest has a place to read/write.
  mkdir -p "${NAS_ROOT}/data/samples_raw" "${NAS_ROOT}/duckdb"
  echo "[${PATCH_CODE}] install_ok"
}

patch_verify() {
  echo "[${PATCH_CODE}] verify: dry-run + execute DAG"
  # Dry run (shows planned jobs)
  _snake -n || true
  # Run with mtime triggers so code changes trigger re-run even if outputs exist
  _snake --rerun-triggers mtime -j1
  echo "[${PATCH_CODE}] verify_ok"
}
