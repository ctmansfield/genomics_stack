task_prereqs() {
  say "Installing prerequisites (curl jq aria2 rsync unzip p7zip-full ca-certificates vi)…"
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends \
    curl jq aria2 rsync unzip p7zip-full ca-certificates vim-tiny coreutils findutils gnupg lsb-release
  ok "Prerequisites installed."
}
register_task "install-prereqs" "Apt packages: curl jq aria2 rsync unzip p7zip…" task_prereqs "Installs system packages."
