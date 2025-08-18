# shellcheck shell=bash
randhex() { openssl rand -hex 32; }
task_write_env() {
  local f="$STACK_DIR/.env"
  say "Ensuring .env"
  if [[ -f "$f" ]]; then
    warn ".env exists -> will append missing keys"
  else
    backup_paths "${f#/}" || true
    touch "$f"
  fi

  append_if_missing "$f" "POSTGRES_USER=${POSTGRES_USER:-genouser}"
  append_if_missing "$f" "POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(randhex)}"
  append_if_missing "$f" "POSTGRES_DB=${POSTGRES_DB:-genomics}"
  append_if_missing "$f" "HASURA_GRAPHQL_ADMIN_SECRET=${HASURA_GRAPHQL_ADMIN_SECRET:-$(randhex)}"
  append_if_missing "$f" "HASURA_GRAPHQL_JWT_SECRET={\"type\":\"HS256\",\"key\":\"$(randhex)\"}"
  append_if_missing "$f" "UPLOAD_TOKEN=${UPLOAD_TOKEN:-$(openssl rand -hex 24)}"
  append_if_missing "$f" "METABASE_DB_FILE=/metabase-data/metabase.db"
  ok "env updated at $f"; grep -E '^(POSTGRES_USER|POSTGRES_DB|UPLOAD_TOKEN)=' "$f"
}
register_task "write-env" "Create/patch .env with secure defaults" task_write_env "Writes secrets to .env (backed up first if exists)."
