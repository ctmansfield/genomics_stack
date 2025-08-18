# shellcheck shell=bash
task_up_stack() {
  say "Bringing up stack"
  dc up -d db hasura metabase pgadmin ingest ingest_worker
  dc ps
}
register_task "up" "Start all services (db, hasura, metabase, pgadmin, ingest, worker)" task_up_stack
