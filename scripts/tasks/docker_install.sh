task_docker_install() {
  if command -v docker >/dev/null 2>&1; then ok "docker present"; else
    say "Installing docker.io + docker-compose-plugin"
    sudo apt-get update -y
    sudo apt-get install -y docker.io docker-compose-plugin
    sudo systemctl enable --now docker
    ok "Docker installed."
  fi
  docker --version && docker compose version || true
}
register_task "install-docker" "Install Docker engine + compose plugin" task_docker_install "Installs/starts Docker."
