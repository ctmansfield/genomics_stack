# shellcheck shell=bash
task_install_prereqs() {
  say "Installing prerequisites (idempotent)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    docker.io docker-compose-plugin curl jq aria2 rsync unzip ca-certificates \
    postgresql-client
  systemctl enable --now docker || true
  ok "prereqs installed"
}
register_task "install-prereqs" "Install Docker, compose plugin & CLI tools" task_install_prereqs "Installs/updates system packages."
