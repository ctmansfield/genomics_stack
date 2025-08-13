task_check_prev() {
  say "compose exists?"; [[ -f "$COMPOSE_FILE" ]] && ok "$COMPOSE_FILE present" || warn "missing compose.yml"
  say ".env sanity"; [[ -f "$STACK_DIR/.env" ]] && grep -E '^(POSTGRES_USER|POSTGRES_DB|UPLOAD_TOKEN)=' "$STACK_DIR/.env" || warn "missing keys"
  say "docker"; docker --version || true; dc ps || true
  say "mounted dirs"; ls -ld /mnt/nas_storage/genomics-stack/{db_data,uploads,vep_cache} || true
}
register_task "check-prev" "Summarize what’s already installed/configured" task_check_prev
