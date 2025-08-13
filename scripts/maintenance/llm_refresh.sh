#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-/root/genomics-stack}"
PG_SVC="${PG_SVC:-db}"
PGUSER="${PGUSER:-genouser}"
PGDB="${PGDB:-genomics}"
LLM_MODEL="${LLM_MODEL:-mistral:latest}"
MAX="${MAX:-50}"
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

need(){ command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }; }
need curl; need jq

# find uploads that have agg rows but no LLM rows (or just all with data)
SQL=$'SELECT DISTINCT a.upload_id\n'\
$'FROM anno.vep_agg a\n'\
$'ORDER BY a.upload_id;'
mapfile -t uploads < <(docker compose -f "$COMPOSE_FILE" exec -T "$PG_SVC" \
  psql -U "$PGUSER" -d "$PGDB" -At -c "$SQL" || true)

for u in "${uploads[@]}"; do
  [ -n "$u" ] || continue
  echo "[info] LLM refresh upload_id=$u model=$LLM_MODEL"
  LLM_MODEL="$LLM_MODEL" "$ROOT/scripts/dev/ollama_batch.sh" "$u" "$MAX"
done
echo "[ok] LLM refresh complete"
