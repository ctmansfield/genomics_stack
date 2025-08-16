#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# Config
ROOT=${ROOT:-/root/genomics-stack}
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"
LLM_HOST=${LLM_HOST:-127.0.0.1}
LLM_PORT=${LLM_PORT:-11434}
LLM_MODEL=${LLM_MODEL:-phi3:mini}   # change to mistral / llama3.1 if desired
TEMP=${LLM_TEMP:-0.2}
MAXTOK=${LLM_MAXTOK:-384}

die(){ echo "[error] $*" >&2; exit 1; }
require(){ command -v "$1" >/dev/null || die "missing tool: $1"; }

cmd_llm_summarize(){
  local upload_id="${1:-}"; [ -n "$upload_id" ] || die "usage: genomicsctl.sh llm-summarize <upload_id>"
  require curl; require jq

  # Pull aggregated rows as JSONL
  local sql='
WITH j AS (
  SELECT a.upload_id, a.variant_id, v.rsid, a.symbols, a.impacts, a.consequences, a.clin_sigs,
         a.hgvs_c, a.hgvs_p, a.max_af, a.max_gnomadg_af
  FROM anno.vep_agg a
  JOIN public.variants v ON v.variant_id=a.variant_id
  WHERE a.upload_id = '"$upload_id"'
)
SELECT jsonb_strip_nulls(to_jsonb(j))::text FROM j;
'
  local jsonl
  jsonl=$(docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -At -F $'\t' -v ON_ERROR_STOP=1 -c "$sql")

  if [ -z "$jsonl" ]; then
    echo "[warn] no aggregated rows for upload_id=$upload_id"
    exit 0
  fi

  # Prompt template (few-shot free, deterministic, JSON out)
  read -r -d '' SYSTEM <<'EOS'
You are a careful genetics writing assistant. Generate a layperson summary from provided structured facts only.
Do NOT invent new genes, diseases, or claims. If facts are missing, say so plainly.
Output STRICT JSON with exactly two keys: "lay_summary" (<= 160 chars, one sentence) and "lay_explanation" (2–4 sentences).
EOS

  # Loop rows; call Ollama /api/generate with JSON output
  while IFS= read -r row; do
    [ -n "$row" ] || continue

    # Build user prompt from data (compact and safe)
    data=$(printf '%s' "$row" | jq '.') || continue

    prompt=$(jq -Rs --arg sys "$SYSTEM" --argjson data "$data" \
      '$sys + "\n\nFacts (JSON):\n" + ($data|tostring) + "\n\nReturn JSON now."' <<<"")

    # Request
    resp=$(curl -s "http://$LLM_HOST:$LLM_PORT/api/generate" \
      -H 'Content-Type: application/json' \
      -d @- <<JSON
{
  "model": "$LLM_MODEL",
  "prompt": $prompt,
  "stream": false,
  "format": "json",
  "options": { "temperature": $TEMP, "num_predict": $MAXTOK }
}
JSON
) || true

    # Extract the model's JSON (Ollama returns it as .response string)
    out=$(printf '%s' "$resp" | jq -r '.response' 2>/dev/null || echo '')
    [ -n "$out" ] || { echo "[warn] empty llm response; skipping"; continue; }

    # Validate JSON and perform a couple of guard checks
    lay_summary=$(printf '%s' "$out" | jq -r '.lay_summary // empty' 2>/dev/null || true)
    lay_expl=$(printf '%s' "$out" | jq -r '.lay_explanation // empty' 2>/dev/null || true)
    [ -n "$lay_summary" ] && [ -n "$lay_expl" ] || { echo "[warn] invalid JSON fields; skipping"; continue; }

    # Enforce: do not mention genes not in input
    in_syms=$(printf '%s' "$data" | jq -r '.symbols // [] | join("|")')
    if [ -n "$in_syms" ]; then
      bad=$(printf '%s' "$lay_summary $lay_expl" | grep -Eoi '[A-Z0-9]{2,10}' | tr ' ' '\n' \
        | grep -vE "^($(echo "$in_syms")|rs[0-9]+)$" || true)
      # We keep it simple; you can expand this; currently just warn.
      [ -z "$bad" ] || echo "[warn] extra tokens not in input symbols detected (non-fatal)"
    fi

    # Upsert to DB
    upload=$(printf '%s' "$data" | jq -r '.upload_id')
    variant=$(printf '%s' "$data" | jq -r '.variant_id')
    phash=$(printf '%s' "$prompt" | sha256sum | awk "{print \$1}")

    docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -v ON_ERROR_STOP=1 -c \
      "INSERT INTO anno.llm_summaries(upload_id,variant_id,model,lay_summary,lay_explanation,prompt_hash)
       VALUES ($upload,$variant,'$LLM_MODEL', \$\$$(printf '%s' "$lay_summary" | sed "s/'/''/g")\$\$, \$\$$(printf '%s' "$lay_expl" | sed "s/'/''/g")\$\$, '$phash')
       ON CONFLICT (upload_id,variant_id,model)
       DO UPDATE SET lay_summary=EXCLUDED.lay_summary, lay_explanation=EXCLUDED.lay_explanation, prompt_hash=EXCLUDED.prompt_hash, created_at=now();"
  done <<< "$jsonl"

  echo "[ok] LLM summaries stored for upload_id=$upload_id (model=$LLM_MODEL)"
}

# Registry hook
register_task "llm-summarize" "Generate lay summaries with local LLM" "cmd_llm_summarize" \
"Usage: genomicsctl.sh llm-summarize <upload_id>
Env: LLM_MODEL (default phi3:mini), LLM_TEMP, LLM_MAXTOK, LLM_HOST, LLM_PORT"
