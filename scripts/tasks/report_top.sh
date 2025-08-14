#!/usr/bin/env bash
# Pair-aware Top-N report (risk_hits first, VEP fallback)
set -euo pipefail

cmd_report_top() {
  local u="${1:-}"; local n="${2:-10}"
  [[ -n "$u" ]] || { echo "usage: report-top <upload_id> [N]"; exit 2; }

  local ROOT=${ROOT:-/root/genomics-stack}
  local COMPOSE_FILE="$ROOT/compose.yml"; [[ -f "$ROOT/docker-compose.yml" ]] && COMPOSE_FILE="$ROOT/docker-compose.yml"
  local REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}
  local DIR="$REPORTS_DIR/upload_${u}"
  local TSV="$DIR/top${n}.tsv"
  local HTML="$DIR/top${n}.html"

  mkdir -p "$DIR"

  # Compose the SQL (variables ${u} and ${n} expand here in bash)
  read -r -d '' SQL <<SQL
WITH
risk AS (
  SELECT
    'risk' AS src,
    COALESCE(v.rsid,'-') AS rsid,
    g.symbol,
    r.short_title AS title,
    h.zygosity,
    NULL::text AS consequence,
    NULL::text AS impact,
    r.weight::text AS weight,
    h.score::text  AS score,
    r.evidence_notes AS notes,
    h.score::numeric AS rank_score
  FROM public.risk_hits h
  JOIN public.risk_rules r ON r.rule_id = h.rule_id
  JOIN public.genes      g ON g.gene_id = r.gene_id
  LEFT JOIN public.variants v ON v.variant_id = r.variant_id
  WHERE h.upload_id = ${u}
),
vep_pick AS (
  SELECT DISTINCT ON (COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol))
         'vep' AS src,
         COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, '-') AS rsid,
         NULLIF(j.symbol,'') AS symbol,
         j.consequence AS title,
         NULL::text AS zygosity,
         j.consequence,
         j.impact,
         NULL::text AS weight,
         NULL::text AS score,
         NULLIF(j.clin_sig,'') AS notes,
         (anno.vep_impact_rank(j.impact))*100
           + CASE WHEN NULLIF(j.clin_sig,'') IS NOT NULL THEN 10 ELSE 0 END
           + COALESCE( (1 - NULLIF(j.af,'-')::numeric), 0 )::numeric AS rank_score
  FROM anno.vep_joined j
  WHERE j.upload_id = ${u}
  ORDER BY COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol),
           (anno.vep_impact_rank(j.impact)) DESC NULLS LAST,
           NULLIF(j.clin_sig,'') DESC NULLS LAST
),
unioned AS (
  SELECT * FROM risk
  UNION ALL
  SELECT * FROM vep_pick
),
ranked AS (
  SELECT u.*, ROW_NUMBER() OVER (ORDER BY rank_score DESC NULLS LAST, symbol NULLS LAST, rsid) AS rn
  FROM unioned u
),
topn AS (
  SELECT * FROM ranked WHERE rn <= ${n}
),
present_syms AS (
  SELECT DISTINCT symbol FROM topn WHERE symbol IS NOT NULL AND symbol <> ''
),
sym2gene AS (
  SELECT g.gene_id, g.symbol FROM public.genes g
),
t_with_gid AS (
  SELECT t.*, s2g.gene_id
  FROM topn t
  LEFT JOIN sym2gene s2g ON s2g.symbol = t.symbol
),
row_pairs AS (
  SELECT
    t.rn,
    t.symbol,
    string_agg(DISTINCT CASE WHEN gp.symbol_a = t.symbol THEN gp.symbol_b ELSE gp.symbol_a END, ', ' ORDER BY CASE WHEN gp.symbol_a = t.symbol THEN gp.symbol_b ELSE gp.symbol_a END) AS paired_with
  FROM t_with_gid t
  JOIN public.gene_pairs_named gp
    ON (gp.symbol_a = t.symbol OR gp.symbol_b = t.symbol)
  JOIN present_syms ps
    ON ps.symbol = CASE WHEN gp.symbol_a = t.symbol THEN gp.symbol_b ELSE gp.symbol_a END
  GROUP BY t.rn, t.symbol
),
clustered AS (
  SELECT
    t.*,
    COALESCE(
      LEAST(t.symbol, split_part(p.paired_with, ', ', 1)),
      t.symbol,
      t.rsid
    ) AS cluster_key,
    p.paired_with
  FROM t_with_gid t
  LEFT JOIN row_pairs p ON p.rn = t.rn
)
SELECT
  src,
  COALESCE(rsid,'-')        AS rsid,
  COALESCE(symbol,'-')      AS symbol,
  COALESCE(title,'-')       AS title,
  COALESCE(zygosity,'-')    AS zygosity,
  COALESCE(impact,'-')      AS impact,
  COALESCE(score,'-')       AS score,
  COALESCE(weight,'-')      AS weight,
  COALESCE(paired_with,'-') AS paired_with,
  COALESCE(notes,'-')       AS notes
FROM clustered
ORDER BY cluster_key NULLS LAST, rank_score DESC NULLS LAST, symbol NULLS LAST, rsid;
SQL

  echo "[+] Building Top-${n} for upload_id=${u}"
  {
    echo -e "src\trsid\tsymbol\ttitle\tzygosity\timpact\tscore\tweight\tpaired_with\tnotes"
    docker compose -f "$COMPOSE_FILE" exec -T db           psql -U genouser -d genomics -At -F $'\t' -v ON_ERROR_STOP=1 -c "$SQL"
  } > "$TSV"

  # HTML render
  awk -v title="Top ${n} (upload ${u})" 'BEGIN{
    print "<!doctype html><meta charset=utf-8><title>" title "</title>";
    print "<style>body{font:14px sans-serif;margin:20px} table{border-collapse:collapse;width:100%} th,td{border:1px solid #ccc;padding:6px;} th{background:#f6f6f6;text-align:left}</style>";
    print "<h2>" title "</h2><table><thead><tr>"
  }
  NR==1{
    for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print "</tr></thead><tbody>"; next
  }
  {
    print "<tr>";
    for(i=1;i<=NF;i++){ gsub(/&/,"&amp;",$i); gsub(/</,"&lt;",$i); gsub(/>/,"&gt;",$i); printf "<td>%s</td>", $i }
    print "</tr>";
  }
  END{ print "</tbody></table>" }' FS='\t' OFS='\t' "$TSV" > "$HTML"

  echo "[ok] TSV:  $TSV"
  echo "[ok] HTML: $HTML"
}

# If executed directly, allow standalone run:
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd_report_top "${1:-}" "${2:-10}"
  exit $?
fi

# If sourced by a task runner that provides register_task, register the command
if declare -F register_task >/dev/null 2>&1; then
  register_task "report-top" "Build Top-N report (risk-first; VEP fallback; pair-aware)" "cmd_report_top"
fi
