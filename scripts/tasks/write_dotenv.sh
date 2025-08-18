# shellcheck shell=bash
source "$(dirname "$0")/../lib/overwrite.sh"
randhex(){ openssl rand -hex 32; }

task_write_env() {
  local env="/root/genomics-stack/.env"
  say "Writing .env (idempotent)"
  local pgpass="${POSTGRES_PASSWORD:-$(randhex)}"
  local hasura_admin="${HASURA_GRAPHQL_ADMIN_SECRET:-$(randhex)}"
  local jwt_secret="${HASURA_GRAPHQL_JWT_SECRET:-{"type":"HS256","key":"$(randhex)"} }"

  safe_write_file "$env" <<EOF
POSTGRES_USER=${POSTGRES_USER:-genouser}
POSTGRES_PASSWORD=${pgpass}
POSTGRES_DB=${POSTGRES_DB:-genomics}
HASURA_GRAPHQL_ADMIN_SECRET=${hasura_admin}
HASURA_GRAPHQL_JWT_SECRET=${jwt_secret}
UPLOAD_TOKEN=${UPLOAD_TOKEN:-$(openssl rand -hex 24)}
EOF
}
register_task ".env-write" "Create/refresh /root/genomics-stack/.env (with backups)" task_write_env "Overwrites .env after backing it up."
