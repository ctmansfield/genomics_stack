task_claim() {
  local id="${1:?usage: genomicsctl.sh claim <upload_id> <email> <claim_code>}"
  local email="${2:?}"; local code="${3:?}"
  say "POST /claim"
  curl -sS -X POST http://127.0.0.1:8090/claim -H "Content-Type: application/json" \
    -d "{\"upload_id\":${id},\"email\":\"${email}\",\"claim_code\":\"${code}\"}"
  echo
}
register_task "claim" "Bind email->token using upload_id + claim_code" task_claim
