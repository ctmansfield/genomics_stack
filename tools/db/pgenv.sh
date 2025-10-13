#!/usr/bin/env bash
set -a
[ -f /repos/genomics-stack/.env ] && . /repos/genomics-stack/.env
# map common alternates if present
: "${PGUSER:=${POSTGRES_USER:-}}"
: "${PGPASSWORD:=${POSTGRES_PASSWORD:-}}"
: "${PGDATABASE:=${POSTGRES_DB:-}}"
: "${PGHOST:=${POSTGRES_HOST:-${PGHOST:-127.0.0.1}}}"
: "${PGPORT:=${POSTGRES_PORT:-${PGPORT:-5432}}}"
set +a

missing=()
for v in PGUSER PGPASSWORD PGDATABASE PGHOST PGPORT; do [ -n "${!v}" ] || missing+=("$v"); done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "[pgenv] Missing: ${missing[*]} — edit /repos/genomics-stack/.env" >&2
  return 1 2>/dev/null || exit 1
fi
echo "[pgenv] PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"
