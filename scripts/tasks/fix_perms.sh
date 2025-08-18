# shellcheck shell=bash
task_fix_perms() {
  say "fixing perms on $UPLOADS"
  sudo mkdir -p "$UPLOADS"
  sudo chown -R 1000:1000 "$UPLOADS"
  sudo chmod -R u+rwX,go+rX "$UPLOADS"
  ok "done"
}
register_task "fix-perms" "Ensure /uploads is writable to containers" task_fix_perms "Will chown/chmod the uploads dir."
