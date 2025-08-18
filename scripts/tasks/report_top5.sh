# shellcheck disable=SC1078,SC2140
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT_DIR/lib/common.sh"

task_report_top5() {
  local upload_id="${1:-}"
  if [[ -z "$upload_id" ]]; then err "Usage: report-top5 <upload_id>"; return 2; fi

  say "[+] Building report for upload_id=${upload_id}"

  local OUT_BASE="/mnt/nas_storage/genomics-stack/reports"
  local outdir="${OUT_BASE}/upload_${upload_id}"
  sudo mkdir -p "$outdir"
  sudo chown 1000:1000 "$outdir"
  sudo chmod -R u+rwX,go+rX "${OUT_BASE}"

  local tsv="/tmp/top5_${upload_id}.tsv"
  dc exec -T db psql -U "$PGUSER" -d "$PGDB" -A -F $'\t' -q -v id="${upload_id}" <<'SQL' >"${tsv}"
WITH hits AS (
  SELECT
    s.upload_id,
    rp.gene, rp.rsid, rp.zygosity, rp.risk_allele, rp.weight,
    rp.summary, rp.nutrition,
    s.allele1, s.allele2
  FROM staging_array_calls s
  JOIN risk_panel rp USING (rsid)
  WHERE s.upload_id = :'id'
    AND (
      (rp.zygosity='any' AND (s.allele1 = rp.risk_allele OR s.allele2 = rp.risk_allele)) OR
      (rp.zygosity='het' AND (s.allele1 = rp.risk_allele OR s.allele2 = rp.risk_allele)
                           AND s.allele1 IS DISTINCT FROM s.allele2) OR
      (rp.zygosity='hom' AND  s.allele1 = rp.risk_allele AND s.allele2 = rp.risk_allele)
    )
),
score AS (
  SELECT
    gene,
    SUM(weight)            AS total_weight,
    COUNT(*)               AS variants_hit,
    STRING_AGG(rsid||'('||zygosity||' '||risk_allele||')', ', ' ORDER BY rsid) AS details,
    MAX(summary)           AS summary,
    MAX(nutrition)         AS nutrition
  FROM hits
  GROUP BY gene
)
SELECT gene, total_weight, variants_hit, details, summary, nutrition
FROM score
ORDER BY total_weight DESC, gene ASC
LIMIT 5;
SQL

  if ! [[ -s "$tsv" ]]; then
    warn "No hits found for upload ${upload_id}. (No TSV written)"
    return 0
  fi

  local final_tsv="${outdir}/top5.tsv"
  sudo mv "$tsv" "$final_tsv"

  local html="${outdir}/top5.html"
  sudo bash -lc "cat >'$html' <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Top 5 Risky Genes — Upload ${upload_id}</title>
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Helvetica,Arial,sans-serif;margin:24px}
    h1{margin:0 0 12px}
    p.note{color:#555}
    table{border-collapse:collapse;width:100%;margin-top:12px}
    th,td{border:1px solid #ccc;padding:8px;vertical-align:top}
    th{background:#f6f6f6;text-align:left}
    code{background:#f0f0f0;padding:2px 4px;border-radius:4px}
  </style>
</head>
<body>
  <h1>Top 5 Risky Genes</h1>
  <p class="note">Upload ID: ${upload_id}. Generated on $(date -Is).</p>
  <table>
    <thead>
      <tr>
        <th>Gene</th>
        <th>Total score</th>
        <th># Variants hit</th>
        <th>Variant details</th>
        <th>Summary</th>
        <th>Nutrition</th>
      </tr>
    </thead>
    <tbody>
HTML"

  # TSV columns: gene total_weight variants_hit details summary nutrition
  sudo awk -F $'\t' '
    {
      # HTML-escape each field
      for (i=1;i<=NF;i++){
        gsub(/&/,"&amp;",$i);
        gsub(/</,"&lt;",$i);
        gsub(/>/,"&gt;",$i);
      }
      printf "      <tr><td><b>%s</b></td><td>%s</td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td></tr>\n",
             $1,$2,$3,$4,$5,$6;
    }' "$final_tsv" | sudo tee -a "$html" >/dev/null

  sudo bash -lc "cat >>'$html' <<'HTML'
    </tbody>
  </table>
  <p class="note">Raw TSV: <code>top5.tsv</code> (in same folder).</p>
</body>
</html>
HTML"

  ok "Report written:"
  echo "  ${final_tsv}"
  echo "  ${html}"
}

register_task "report-top5" "Generate Top 5 risky genes report (HTML + TSV)" task_report_top5 "Usage: report-top5 <upload_id>"
