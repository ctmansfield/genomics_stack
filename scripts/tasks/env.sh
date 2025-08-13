#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
task_env_dump() {
  cat <<EOF
ROOT=$ROOT
ENV_FILE=$ENV_FILE
PGHOST=$PGHOST
PGPORT=$PGPORT
PGUSER=$PGUSER
PGDB=$PGDB
BACKUP_DIR=$BACKUP_DIR
UPLOADS_DIR=$UPLOADS_DIR
CACHE_ROOT=$CACHE_ROOT
EOF
}
register_task "env" "Show controller environment" task_env_dump
