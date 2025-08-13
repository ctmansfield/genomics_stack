#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-/root/genomics-stack}"
PG_SVC="${PG_SVC:-db}"
PGUSER="${PGUSER:-genouser}"
PGDB="${PGDB:-genomics}"
REPORTS_DIR="${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}"
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

SQL_IDS=$'SELECT DISTINCT upload_id FROM anno.vep_joined ORDER BY 1;'
mapfile -t uploads < <(docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" \
  psql -U "$PGUSER" -d "$PGDB" -At -c "$SQL_IDS" || true)

mkdir -p "$REPORTS_DIR/research_todo"
for u in "${uploads[@]}"; do
  [ -n "$u" ] || continue
  out="$REPORTS_DIR/research_todo/upload_${u}_genes.txt"
  docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" \
    psql -U "$PGUSER" -d "$PGDB" -At -c \
"SELECT DISTINCT COALESCE(NULLIF(symbol,''),'(no_symbol)') FROM anno.vep_joined WHERE upload_id=$u ORDER BY 1;" \
  > "$out"
  echo "[ok] wrote $out"
done
