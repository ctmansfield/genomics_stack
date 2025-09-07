#!/usr/bin/env bash
set -euo pipefail
: "${REPO_ROOT:?}"; : "${NAS_ROOT:?}"

if command -v snakemake >/dev/null 2>&1; then
  sm_cmd="snakemake"
else
  sm_cmd="python -m snakemake"
fi

$sm_cmd -s "$REPO_ROOT/components/orch/Snakefile" -n
$sm_cmd -s "$REPO_ROOT/components/orch/Snakefile" -j1
[ -f "$NAS_ROOT/duckdb/genomics.duckdb" ] && echo "e2e_stub_ok"
