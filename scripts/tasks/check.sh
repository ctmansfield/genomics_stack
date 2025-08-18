# shellcheck shell=bash
task_check() {
  say "compose ps"; dc ps || true
  say "ports 8090/5433"; ss -lntp | egrep ':8090|:5433' || true
  say "healthz"; curl -sS http://127.0.0.1:8090/healthz || true; echo
  say "DB ping"
  PGPASSWORD="$PGPASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$PGUSER" -d "$PGDB" -Atc "select 'db_ok', now();" || err "DB ping failed"
  say "uploads perms"; sudo mkdir -p "$UPLOADS"; sudo test -w "$UPLOADS" && ok "writable" || warn "NOT writable"
}
register_task "check" "Show status, ports, healthz, DB ping, perms" task_check
