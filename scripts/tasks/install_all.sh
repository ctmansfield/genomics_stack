task_install_all() {
  task_install_prereqs
  task_setup_dirs
  task_write_env
  task_write_compose
  task_build_images
  task_up_stack
  task_db_schema
  ok "Core stack is up. Optional next: vep-cache, vep-selftest"
}
register_task "install-all" "Run full install steps (idempotent)" task_install_all "Installs packages, writes config, builds & starts services."
