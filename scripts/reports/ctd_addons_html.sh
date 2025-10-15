#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-reports/upload_2}"
TOPN_TABLE="${TOPN_TABLE:-100}"
mkdir -p "$OUTDIR"

DDI="${OUTDIR}/ctd_ddi_badges.csv"
PTH="${OUTDIR}/ctd_top_pathways_per_chemical.csv"
CNT="${OUTDIR}/ctd_unique_counts.csv"
BODY="${OUTDIR}/ctd_addons_body.html"
HTML="${OUTDIR}/ctd_addons.html"

need(){ for f in "$@"; do [[ -f "$f" ]] || { echo "[missing] $f"; exit 1; }; done; }
need "$DDI" "$PTH" "$CNT"

# tiny CSV→HTML table helper (first row header, limit rows)
table_from_csv(){
  local csv="$1" limit="${2:-50}"
  awk -v lim="$limit" -F',' '
    BEGIN{
      print "<div class=\"tblwrap\"><table><thead>"
    }
    NR==1{
      printf "<tr>"; for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print "</tr></thead><tbody>"
      next
    }
    NR>1{
      if(NR-1<=lim){
        printf "<tr>"; for(i=1;i<=NF;i++) printf "<td>%s</td>", $i; print "</tr>"
      }
    }
    END{ print "</tbody></table></div>" }
  ' "$csv"
}

style='<style>
.tblwrap{overflow:auto;max-height:520px;border:1px solid #eee}
table{border-collapse:collapse;width:100%;font:14px/1.4 system-ui,Segoe UI,Arial}
th,td{border:1px solid #ddd;padding:6px 8px}
th{background:#f7f7f7;text-align:left}
h2{margin:28px 0 6px}
.note{color:#666;font-size:12px;margin:0 0 10px}
.kv{display:grid;grid-template-columns:auto auto;gap:6px 16px;max-width:420px}
.kv div{padding:2px 0;border-bottom:1px dashed #eee}
.badge{display:inline-block;padding:2px 8px;border:1px solid #ccc;border-radius:999px;font-size:12px}
.badge.warn{background:#fff4e6;border-color:#ffd6a6}
.badge.ok{background:#e8f7e8;border-color:#c5ebc5}
</style>'

counts_html=$(awk -F',' 'NR==2{
  printf("<div class=\"kv\">\
<div>Edges (FULL)</div><div>%s</div>\
<div>Edges (STRICT)</div><div>%s</div>\
<div>Edges pruned</div><div>%s</div>\
<div>Pairs (FULL)</div><div>%s</div>\
<div>Pairs (STRICT)</div><div>%s</div>\
<div>Pairs pruned</div><div>%s</div>\
</div>", $1,$2,$3,$4,$5,$6)
}' "$CNT")

ddi_note='<div class="note">Badge logic combines STRICT “activates/inhibits” and FULL ↑/↓ expression on key ADME genes (CYPs, ABCB1, SLCO1B1, UGTs).\
 <span class="badge warn">Check DDI: ↑/↓/mixed</span> indicates potential induction/inhibition risk worth ADME/Tox review.</div>'

pth_note='<div class="note">Top-3 Reactome pathways per compound using STRICT edges (distinct genes per pathway).</div>'

{
  echo "$style"
  echo "<h2>Dataset shape (FULL vs STRICT)</h2>$counts_html"
  echo "<h2>DDI badges (top ${TOPN_TABLE})</h2>$ddi_note"
  table_from_csv "$DDI" "$TOPN_TABLE"
  echo "<h2>Top-3 Reactome pathways per chemical (top ${TOPN_TABLE})</h2>$pth_note"
  table_from_csv "$PTH" "$TOPN_TABLE"
} > "$BODY"

printf '<!doctype html><meta charset="utf-8"><title>CTD add-ons</title>%s' "$(cat "$BODY")" > "$HTML"

echo "[ok] Wrote: $BODY"
echo "[ok] Wrote: $HTML"
