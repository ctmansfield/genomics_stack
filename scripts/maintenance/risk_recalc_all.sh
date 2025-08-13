#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-/root/genomics-stack}
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"
PGUSER=${PGUSER:-genouser}
PGDB=${PGDB:-genomics}
REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}

DC=(docker compose -f "$COMPOSE_FILE")
PSQL_JSON=("${DC[@]}" exec -T db psql -U "$PGUSER" -d "$PGDB" -At -v ON_ERROR_STOP=1 -c)

say(){ echo "[info] $*"; }
ok(){ echo "[ok] $*"; }

# Prefer the DB-native function if present
HAS_FN="$("${PSQL_JSON[@]}" "select exists (select 1 from pg_proc where proname='risk_hits_recalc_all' and pg_function_is_visible(oid));")"
if echo "$HAS_FN" | grep -qi t; then
  say "calling public.risk_hits_recalc_all() in database"
  "${DC[@]}" exec -T db psql -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 \
    -c "select * from public.risk_hits_recalc_all();"
  ok "risk recompute complete"
  exit 0
fi

# Fallback (shell discovery → loop)
say "DB function not found; using shell fallback discovery"

has_tbl(){ "${PSQL_JSON[@]}" "select to_regclass('public.$1') is not null" | grep -qi t; }
has_col(){ "${PSQL_JSON[@]}" "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='$1' and column_name='$2')" | grep -qi t; }

UPLOAD_IDS=""
if has_tbl genotypes && has_col genotypes upload_id; then
  UPLOAD_IDS="$("${PSQL_JSON[@]}" "select distinct upload_id from public.genotypes order by 1" || true)"
fi
if [ -z "$UPLOAD_IDS" ] && has_tbl staging_array_calls && has_col staging_array_calls upload_id; then
  UPLOAD_IDS="$("${PSQL_JSON[@]}" "select distinct upload_id from public.staging_array_calls order by 1" || true)"
fi
if [ -z "$UPLOAD_IDS" ] && has_tbl risk_hits; then
  UPLOAD_IDS="$("${PSQL_JSON[@]}" "select distinct upload_id from public.risk_hits order by 1" || true)"
fi
if [ -z "$UPLOAD_IDS" ] && [ -d "$REPORTS_DIR" ]; then
  UPLOAD_IDS="$(find "$REPORTS_DIR" -maxdepth 1 -type d -name 'upload_*' -printf '%f\n' \
                  | sed -n 's/^upload_//p' | sort -n || true)"
fi

[ -n "$UPLOAD_IDS" ] || { echo "[error] couldn't find any upload ids"; exit 1; }

say "recomputing: $(echo "$UPLOAD_IDS" | tr '\n' ' ')"
for id in $UPLOAD_IDS; do
  "${DC[@]}" exec -T db psql -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 \
    -c "select risk_hits_recalc($id);" >/dev/null
done
ok "risk recompute complete"
