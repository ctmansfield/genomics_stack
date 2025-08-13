task_setup_dirs() {
  say "Creating directories"
  sudo mkdir -p \
    /mnt/nas_storage/genomics-stack/{db_data,uploads,init,hasura_metadata,metabase_data,pgadmin_data,vep_cache/tmp} \
    "$BACKUP_DIR"
  sudo chown -R 1000:1000 /mnt/nas_storage/genomics-stack/uploads
  sudo chmod -R u+rwX,go+rX /mnt/nas_storage/genomics-stack/uploads
  ok "directories ready"
}
register_task "setup-dirs" "Create data/cache/backup directories and perms" task_setup_dirs
