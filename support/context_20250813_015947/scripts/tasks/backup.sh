task_backup() {
  require_cmd tar
  local BDIR="${BACKUP_DIR:-/mnt/nas_storage/genomics-stack/backups}"
  sudo mkdir -p "$BDIR"

  local ts; ts=$(date +%Y%m%d_%H%M%S)
  local db_dump="$BDIR/db_${PGDB}_${ts}.dump"
  local files_tar="$BDIR/files_${ts}.tgz"

  say "DB dump -> $db_dump"
  dc exec -T db pg_dump -U "$PGUSER" -d "$PGDB" -Fc > "$db_dump"
  ok "DB dumped"

  say "Tar configs + uploads + minimal cache listing"
  tar -C / -czf "$files_tar" \
    "root/genomics-stack/compose.yml" \
    "root/genomics-stack/.env" \
    "root/genomics-stack/ingest" \
    "root/genomics-stack/ingest_worker" \
    "mnt/nas_storage/genomics-stack/uploads"
  ok "Archive: $files_tar"

  echo
  ok "Backup completed"
  ls -lh "$db_dump" "$files_tar"
}
register_task 'backup' 'Backup DB + uploads + configs' task_backup 'Creates new backup files.'
