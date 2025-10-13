#!/usr/bin/env bash
set -a; [ -f /repos/genomics-stack/.env ] && . /repos/genomics-stack/.env; set +a
: "${PGHOST:=127.0.0.1}"; : "${PGPORT:=5432}"
for v in PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE; do
  [ -n "${!v}" ] || { echo "[pgenv] Missing $v"; return 1; }
done
echo "[pgenv] PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"
