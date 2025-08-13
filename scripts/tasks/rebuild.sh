task_rebuild() {
  local svc="${1:-ingest}"
  say "rebuild+up $svc"; dc build "$svc"; dc up -d "$svc"; dc ps
}
register_task "rebuild" "Rebuild image and up -d (default ingest)" task_rebuild "Image rebuild & restart."
