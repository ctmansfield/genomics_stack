#!/usr/bin/env bash
set -euo pipefail
: "${REPO_ROOT:?}"; : "${NAS_ROOT:?}"

snakemake -s "$REPO_ROOT/components/orch/Snakefile" -n
snakemake -s "$REPO_ROOT/components/orch/Snakefile" -j1

[ -f "$NAS_ROOT/duckdb/genomics.duckdb" ] && echo "e2e_stub_ok"
