#!/usr/bin/env bash
set -euo pipefail
OUTDIR="reports/upload_2"
CSV="$OUTDIR/ctd_ddi_patient_overlay.csv"
HTML="$OUTDIR/ctd_ddi_patient_overlay.html"
BODY="$OUTDIR/ctd_ddi_patient_overlay_body.html"

mkdir -p "$OUTDIR"

# Build BODY
{
  cat <<'CSSHTML'
<!doctype html><meta charset="utf-8"><title>DDI overlay (patient)</title>
<style>
.tblwrap{overflow:auto;max-height:520px;border:1px solid #eee}
table{border-collapse:collapse;width:100%;font:14px/1.45 system-ui,Segoe UI,Arial}
th,td{border:1px solid #ddd;padding:6px 8px}
th{background:#f7f7f7;text-align:left}
.badge{display:inline-block;padding:2px 8px;border:1px solid #ccc;border-radius:999px;font-size:12px}
.badge.up{background:#fff4e6;border-color:#ffd6a6}
.badge.down{background:#ffecec;border-color:#ffbdbd}
.badge.mix{background:#e6f2ff;border-color:#b5d5ff}
.note{color:#666;font-size:12px;margin:0 0 10px}
</style>
<h2>Patient-specific DDI overlay</h2>
<div class='note'>Badges summarize likely direction on patient ADME genes (rare/high-impact variants). “Up” ≈ mostly increases-expression edges on those genes; “Down” ≈ mostly decreases-expression; “Mix” ≈ neither direction dominates.</div>
<div class='tblwrap'><table><thead><tr>
<th>Drug</th><th>Badge</th><th>↑ inc</th><th>↓ dec</th><th>± affects</th><th>Total ADME hits</th>
</tr></thead><tbody>
CSSHTML

  if [[ ! -s "$CSV" ]]; then
    echo "<tr><td colspan='6'><em>No patient ADME signals available (CSV empty).</em></td></tr>"
  else
    # skip header, emit rows
    tail -n +2 "$CSV" | awk -F',' '{
      drug=$1; badge=$2; inc=$3; dec=$4; ambig=$5; hits=$6;
      printf("<tr><td>%s</td><td><span class=\"badge %s\">%s</span></td><td class=\"num\">%s</td><td class=\"num\">%s</td><td class=\"num\">%s</td><td class=\"num\">%s</td></tr>\n",
             drug, badge, badge, inc, dec, ambig, hits);
    }'
  fi
  echo "</tbody></table></div>"
} > "$BODY"

# Wrap BODY as a standalone page too
printf "<!doctype html><meta charset='utf-8'><title>DDI overlay (patient)</title><body>%s</body>" "$(cat "$BODY")" > "$HTML"

echo "[ok] Wrote $BODY"
echo "[ok] Wrote $HTML"
