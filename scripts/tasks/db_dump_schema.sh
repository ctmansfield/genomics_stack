#!/usr/bin/env bash
# Dump live DB schema into repo (schema-only), focusing on allowed schemas to avoid permission issues.
# Usage:
#   scripts/tasks/db_dump_schema.sh            # uses PG_DSN or PG* envs
# Env:
#   PG_DSN or PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE
#   SCHEMAS="public,anno"   # comma-separated whitelist; defaults to public,anno
#   FULL_DUMP=1              # optional: attempt full-db dump (may fail on restricted schemas)
# Output:
#   sql/schema_dump/<schema>_YYYYmmddHHMMSS.sql (for each schema)
#   sql/schema_current.sql (concatenated latest of whitelisted schemas)
set -euo pipefail

# Resolve repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT/sql/schema_dump"
mkdir -p "$OUT_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need pg_dump
need psql
need date

# Build connection options
CONN_ARG=""
export PGPASSWORD="${PGPASSWORD:-}"
if [[ -n "${PG_DSN:-}" ]]; then
  # Extract password for pg_dump env var to avoid password prompt
  if [[ -z "$PGPASSWORD" ]]; then
    PGPASSWORD="$(echo "$PG_DSN" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p')"
    export PGPASSWORD
  fi
  CONN_ARG=( -d "$PG_DSN" )
else
  : "${PGHOST:?PGHOST not set}"; : "${PGPORT:?PGPORT not set}"; : "${PGUSER:?PGUSER not set}"; : "${PGDATABASE:?PGDATABASE not set}"
  CONN_ARG=( -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" )
fi

TS="$(date +%Y%m%d%H%M%S)"
LATEST="$ROOT/sql/schema_current.sql"
common_flags=( --schema-only --no-owner --no-privileges )

# Optional full dump (may fail if not permitted on some schemas)
if [[ "${FULL_DUMP:-}" == "1" ]]; then
  FULL_OUT="$OUT_DIR/schema_${TS}.sql"
  echo "[opt] Attempting full schema dump -> $FULL_OUT"
  if pg_dump "${CONN_ARG[@]}" "${common_flags[@]}" -N 'pg_*' -N 'information_schema' -f "$FULL_OUT"; then
    echo "[ok] Full dump completed"
  else
    echo "[warn] Full dump failed (likely permissions); continuing with whitelisted schemas" >&2
  fi
fi

# Whitelist schemas (default: public,anno)
SCHEMAS_CSV="${SCHEMAS:-public,anno}"
IFS=',' read -r -a SCHEMAS_ARR <<< "$SCHEMAS_CSV"

# Start/overwrite the consolidated current file
: > "$LATEST"
echo "-- Consolidated schema (whitelist: $SCHEMAS_CSV) @ $TS" >> "$LATEST"

# Dump each whitelisted schema if present
for SCH in "${SCHEMAS_ARR[@]}"; do
  SCH_TRIM="${SCH// /}"
  if [[ -z "$SCH_TRIM" ]]; then continue; fi
  if psql "${CONN_ARG[@]}" -Atqc "SELECT to_regnamespace('$SCH_TRIM') IS NOT NULL" 2>/dev/null | grep -q '^t$'; then
    OUT_FILE="$OUT_DIR/${SCH_TRIM}_${TS}.sql"
    echo "[dump] $SCH_TRIM -> $OUT_FILE"
    pg_dump "${CONN_ARG[@]}" "${common_flags[@]}" -n "$SCH_TRIM" -f "$OUT_FILE"
    echo -e "\n-- >>> BEGIN SCHEMA: $SCH_TRIM\n" >> "$LATEST"
    cat "$OUT_FILE" >> "$LATEST"
    echo -e "\n-- <<< END SCHEMA: $SCH_TRIM\n" >> "$LATEST"
  else
    echo "[skip] Schema '$SCH_TRIM' not present"
  fi
done

echo "[ok] Schema dumps written under $OUT_DIR"
echo "[ok] Consolidated latest at $LATEST"
