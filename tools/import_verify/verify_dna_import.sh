#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
# Verify that a DNA/variants file was fully imported into Postgres using libpq env vars.
# Usage:
#   tools/import_verify/verify_dna_import.sh \
#     --file /path/to/variants.tsv[.gz] \
#     --table public.annotated_variants_staging \
#     [--header true|false]
#
# Reads PGHOST/PGPORT/PGDATABASE/PGUSER from env.d/*.env via tools/env/load_env.sh
# Password comes from ~/.pgpass (chmod 600). No passwords on CLI.

# Load env (PGHOST, PGPORT, PGDATABASE, PGUSER, etc.)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tools/env/load_env.sh"

# Minimal conn sanity
: "${PGHOST:?PGHOST not set}"; : "${PGPORT:?PGPORT not set}"
: "${PGDATABASE:?PGDATABASE not set}"; : "${PGUSER:?PGUSER not set}"

file=""
table="public.annotated_variants_staging"
has_header="true"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)   file="$2"; shift 2;;
    --table)  table="$2"; shift 2;;
    --header) has_header="$2"; shift 2;;
    *) echo "[ERR] unknown arg: $1" >&2; exit 2;;
  esac
done

# Sanity
[[ -n "$file" ]] || { echo "[ERR] --file required" >&2; exit 2; }
[[ -f "$file" ]] || { echo "[ERR] file not found: $file" >&2; exit 2; }

manifest="${file}.manifest.json"
[[ -f "$manifest" ]] || { echo "[ERR] Manifest missing: $manifest" >&2; exit 2; }

# Read manifest
expected_rows=$(jq -r '.expected_rows' "$manifest")
sha256=$(jq -r '.sha256' "$manifest")
echo "[verify] File: $file"
echo "[verify] Table: $table"
echo "[verify] Expected rows: $expected_rows"
echo "[verify] SHA256: $sha256"

# Helper to run psql with inherited PG* env
psqlq() { psql -Atqc "$1"; }

# 1) Row count check
db_rows=$(psqlq "SELECT COUNT(*) FROM $table")
echo "[verify] DB rows: $db_rows"
[[ "$db_rows" == "$expected_rows" ]] || { echo "[FAIL] Row count mismatch"; exit 10; }

# 2) Basic shape check (required fields present)
shape_ok=$(psqlq "
WITH v AS (
  SELECT
    COUNT(*) FILTER (WHERE chrom IS NULL OR chrom='') AS bad_chrom,
    COUNT(*) FILTER (WHERE pos   IS NULL)            AS bad_pos,
    COUNT(*) FILTER (WHERE ref   IS NULL OR ref='')  AS bad_ref,
    COUNT(*) FILTER (WHERE alt   IS NULL OR alt='')  AS bad_alt
  FROM $table
)
SELECT (bad_chrom=0 AND bad_pos=0 AND bad_ref=0 AND bad_alt=0)::int FROM v;")
[[ "$shape_ok" == "1" ]] || { echo "[FAIL] Shape check failed (chrom/pos/ref/alt)"; exit 11; }

# 3) Optional: per-chrom histogram comparison (if you created it)
hist="${file}.by_chrom.txt"
if [[ -f "$hist" ]]; then
  echo "[verify] Comparing per-chrom counts with ${hist}..."
  tmp_db_hist=$(mktemp)
  psql -Atc "SELECT chrom, COUNT(*) FROM $table GROUP BY chrom ORDER BY chrom" > "$tmp_db_hist"
  if diff -u "$hist" "$tmp_db_hist" >/dev/null; then
    echo "[OK] Per-chrom counts match"
  else
    echo "[FAIL] Per-chrom mismatch"
    echo "  File histogram: $hist"
    echo "  DB histogram:   $tmp_db_hist"
    exit 12
  fi
fi

echo "[OK] Import verified in DB for $file"
