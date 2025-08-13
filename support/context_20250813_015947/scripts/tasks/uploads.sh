#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

task_uploads_list() {
  dc exec -T db psql -U "${PGUSER}" -d "${PGDB}" -c \
"select id, original_name, kind, status, user_email, left(notes,80) notes
 from uploads order by id desc limit 20;"
}
register_task "uploads-list" "List recent uploads in DB" task_uploads_list
