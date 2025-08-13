#!/usr/bin/env bash
set -euo pipefail

# load common helpers + 'dc' alias
COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)/lib/common.sh"
[ -r "$COMMON" ] && . "$COMMON"

psql_db(){ dc exec -T db psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" "$@"; }
ensure_int(){ [[ "$1" =~ ^[0-9]+$ ]] || { err "ID must be a positive integer"; exit 2; }; }

# Soft delete: clear staging rows; if the row is a keeper we set status=deleted,
# if it's already duplicate we DO NOT change status (avoids unique collision).
task_upload_soft_delete() {
  local id="${1:-}"; [ -z "$id" ] && read -r -p "Upload ID to SOFT delete: " id
  ensure_int "$id"

  say "[+] Preview:"
  psql_db -c "select id, original_name, user_email, status, left(coalesce(notes,''),120) notes from uploads where id=$id;"

  # is this row a 'duplicate' already?
  local is_dup
  is_dup=$(psql_db -At -c "select (status='duplicate')::int from uploads where id=$id;")

  confirm_or_exit "Soft delete upload $id (clear staged rows, $( [ "$is_dup" = "1" ] && echo 'keep status=duplicate' || echo "mark status=deleted" ))?"

  say "Deleting staged rows..."
  psql_db -c "delete from staging_array_calls where upload_id=$id;"

  if [ "$is_dup" = "1" ]; then
    say "Row is already duplicate; leaving status as-is and appending note."
    psql_db -c "update uploads set notes=coalesce(notes,'')||' soft_deleted_at='||now()||';' where id=$id;"
  else
    say "Marking upload as deleted."
    psql_db -c "update uploads set status='deleted', notes=coalesce(notes,'')||' soft_deleted_at='||now()||';' where id=$id;"
  fi

  ok "Soft delete done."
  psql_db -c "select u.id, u.original_name, u.status, left(coalesce(u.notes,''),120) notes,
                     (select count(*) from staging_array_calls where upload_id=$id) as staged_rows
                from uploads u where u.id=$id;"
}

# Hard delete: remove staged rows + upload row; try to remove stored file if path exists
task_upload_hard_delete() {
  local id="${1:-}"; [ -z "$id" ] && read -r -p "Upload ID to HARD delete: " id
  ensure_int "$id"

  local stored=""
  stored=$(psql_db -At -c "select stored from uploads where id=$id;" 2>/dev/null || true)

  say "[+] Preview:"
  psql_db -c "select id, original_name, user_email, status, left(coalesce(notes,''),120) notes from uploads where id=$id;"
  [ -n "$stored" ] && say "Stored file: $stored"

  confirm_or_exit "HARD delete upload $id (DB row + staged rows + file if tracked)?"

  psql_db -c "begin;
                delete from staging_array_calls where upload_id=$id;
                delete from uploads where id=$id;
              commit;"

  if [ -n "$stored" ]; then
    say "Removing file inside ingest container: $stored"
    dc exec -T ingest bash -lc "rm -f -- \"$stored\" || true"
  fi
  ok "Hard delete completed for ID=$id."
}

register_task "upload-soft-delete" "Soft delete a single upload" task_upload_soft_delete "Clears staging rows; keeps 'duplicate' status or marks keeper as 'deleted'."
register_task "upload-hard-delete" "Hard delete a single upload (DB + file)" task_upload_hard_delete "Deletes staging rows, the upload row, and file if tracked."
