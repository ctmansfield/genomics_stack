#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-/root/genomics-stack}"
PG_SVC="${PG_SVC:-db}"
PGUSER="${PGUSER:-genouser}"
PGDB="${PGDB:-genomics}"
BACKUP_DIR="${BACKUP_DIR:-/mnt/nas_storage/genomics-stack/backups}"
RET_DAYS="${RET_DAYS:-14}"
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

ts="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
out="$BACKUP_DIR/${PGDB}_${ts}.dump"
log="$BACKUP_DIR/${PGDB}_${ts}.log"

{
  echo "[info] pg_dump -Fc $PGDB -> $out"
  docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" \
    pg_dump -U "$PGUSER" -d "$PGDB" -Fc -f "/tmp/${PGDB}_${ts}.dump"
  docker compose -f "$COMPOSE_FILE" cp "$PG_SVC:/tmp/${PGDB}_${ts}.dump" "$out"
  docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" rm -f "/tmp/${PGDB}_${ts}.dump"
  echo "[info] keeping ${RET_DAYS} days"
  find "$BACKUP_DIR" -name "${PGDB}_*.dump" -type f -mtime +"$RET_DAYS" -print -delete || true
  echo "[ok] backup: $out"
} | tee -a "$log"
