#!/usr/bin/env bash
set -euo pipefail
DB="${DUCKDB_DB:-/mnt/nas_storage/genomics/duckdb/genomics.duckdb}"

command -v duckdb >/dev/null || { echo "[DDB-05] duckdb CLI not found"; exit 2; }
test -f "$DB" || { echo "[DDB-05] DB not found: $DB"; exit 3; }

duckdb "$DB" < views.sql
echo "[DDB-05] views installed."
