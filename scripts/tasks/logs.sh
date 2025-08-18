# shellcheck shell=bash
task_logs() {
  local svc="${1:-ingest}"
  say "logs: $svc (last 200)"; dc logs --tail=200 "$svc" || true
}
register_task "logs" "Tail last 200 lines of a service (default ingest)" task_logs
