#!/usr/bin/env bash
set -euo pipefail

upload_id="${1:-}"; limit="${2:-50}"
[[ "$upload_id" =~ ^[0-9]+$ ]] || { echo "usage: ollama_batch.sh <upload_id:int> [limit=50]"; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "limit must be an integer"; exit 2; }

ROOT=${ROOT:-/root/genomics-stack}
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"

LLM_MODEL="${LLM_MODEL:-mistral:latest}"
LLM_HOST="${LLM_HOST:-127.0.0.1}"
LLM_PORT="${LLM_PORT:-11434}"
LLM_TEMP="${LLM_TEMP:-0.2}"
LLM_MAXTOK="${LLM_MAXTOK:-384}"

LOGDIR="/mnt/nas_storage/genomics-stack/reports/upload_${upload_id}/anno/llm_batch"
mkdir -p "$LOGDIR"

# Pull aggregated rows as JSONL (no psql placeholders)
read -r -d '' SQL <<SQL
WITH j AS (
  SELECT a.upload_id, a.variant_id, v.rsid, a.symbols, a.impacts, a.consequences, a.clin_sigs,
         a.hgvs_c, a.hgvs_p, a.max_af, a.max_gnomadg_af
  FROM anno.vep_agg a
  JOIN public.variants v ON v.variant_id=a.variant_id
  WHERE a.upload_id = ${upload_id}
)
SELECT jsonb_strip_nulls(to_jsonb(j))::text FROM j;
SQL

jsonl="$(docker compose -f "$COMPOSE_FILE" exec -T db \
  psql -U genouser -d genomics -At -v ON_ERROR_STOP=1 -c "$SQL")"

if [ -z "$jsonl" ]; then
  echo "[warn] no aggregated rows for upload_id=$upload_id"
  exit 0
fi

# System prompt
read -r -d '' SYSTEM <<'EOS'
You are a careful genetics writing assistant. Use ONLY the given facts (JSON).
Do NOT invent new claims. If facts are missing, say so plainly.
Return STRICT JSON with exactly:
  "lay_summary"     (<=160 chars, one sentence)
  "lay_explanation" (2–4 sentences, plain English)
EOS

i=0; processed=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  i=$((i+1)); [ "$i" -le "$limit" ] || break

  data="$(printf '%s' "$row" | jq '.')"
  rsid="$(printf '%s' "$data" | jq -r '.rsid // ("no_rsid_" + (now|tostring))')"
  vid="$(printf '%s' "$data" | jq -r '.variant_id')"

  prompt="$(jq -n --arg sys "$SYSTEM" --argjson data "$data" \
    '$sys+"\n\nFacts (JSON):\n"+($data|tostring)+"\n\nReturn JSON now."')"
  echo "$prompt" > "$LOGDIR/${i}_${rsid}_prompt.txt"

  req="$(jq -n --arg model "$LLM_MODEL" --arg prompt "$prompt" \
        --argjson t "$LLM_TEMP" --argjson n "$LLM_MAXTOK" \
        '{model:$model,prompt:$prompt,stream:false,format:"json",options:{temperature:$t,num_predict:$n}}')"

  resp="$(curl -s "http://$LLM_HOST:$LLM_PORT/api/generate" \
         -H 'Content-Type: application/json' -d "$req" || true)"
  printf '%s\n' "$resp" > "$LOGDIR/${i}_${rsid}_resp.json"

  body="$(printf '%s' "$resp" | jq -r '.response // empty' 2>/dev/null || true)"
  [ -n "$body" ] || { echo "[warn] empty response for $rsid"; continue; }

  lay_summary="$(printf '%s' "$body" | jq -r '.lay_summary // empty' 2>/dev/null || true)"
  lay_expl="$(printf '%s' "$body" | jq -r '.lay_explanation // empty' 2>/dev/null || true)"
  [ -n "$lay_summary" ] && [ -n "$lay_expl" ] || { echo "[warn] invalid JSON fields for $rsid"; continue; }

  phash="$(printf '%s' "$prompt" | sha256sum | awk '{print $1}')"
  esc_sum="$(printf '%s' "$lay_summary" | sed "s/'/''/g")"
  esc_expl="$(printf '%s' "$lay_expl" | sed "s/'/''/g")"

  docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -v ON_ERROR_STOP=1 -c "
    INSERT INTO anno.llm_summaries(upload_id,variant_id,model,lay_summary,lay_explanation,prompt_hash)
    VALUES (${upload_id},${vid},'${LLM_MODEL}', $$${esc_sum}$$, $$${esc_expl}$$, '${phash}')
    ON CONFLICT (upload_id,variant_id,model)
    DO UPDATE SET lay_summary=EXCLUDED.lay_summary,
                  lay_explanation=EXCLUDED.lay_explanation,
                  prompt_hash=EXCLUDED.prompt_hash,
                  created_at=now();"

  processed=$((processed+1))
  echo "[ok] $i/$limit  $rsid  → stored"
done <<< "$jsonl"

echo "[done] processed=$processed (requested=$limit) for upload_id=$upload_id, model=$LLM_MODEL"
