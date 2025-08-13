task_whoami() {
  local token="${1:?usage: genomicsctl.sh whoami <token>}"
  say "GET /whoami"
  curl -sS -H "Authorization: Bearer ${token}" http://127.0.0.1:8090/whoami
  echo
}
register_task "whoami" "Check token owner" task_whoami
