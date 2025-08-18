# shellcheck shell=bash
task_stack_up() {
  say "Compose config check"; dc config >/dev/null && ok "OK"
  say "Build services"; dc build ingest ingest_worker
  say "Up services"; dc up -d db hasura metabase pgadmin ingest ingest_worker
  dc ps
}
register_task "stack-up" "Build and start the full stack" task_stack_up "Starts/updates running services."
