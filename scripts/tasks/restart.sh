task_restart() {
  local svc="${1:-ingest}"
  say "restarting $svc"; dc restart "$svc"; dc ps
}
register_task "restart" "Restart a service (default ingest)" task_restart "Service will be restarted."
