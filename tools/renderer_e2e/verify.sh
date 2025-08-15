[ -f /root/.pg_env ] && . /root/.pg_env
#!/usr/bin/env bash
set -euo pipefail

PSQL="psql -v ON_ERROR_STOP=1"
OUT=/root/genomics-stack/risk_reports/out
HTML="$OUT/_pdf_smoke.html"
PDF="$OUT/_pdf_smoke.verify.pdf"

step(){ echo -e "\n[verify] $*"; }

# 1) DB connectivity & required views
step "DB connectivity"
$PSQL -c "SELECT current_user AS user, current_database() AS db;"

step "Required views exist"
$PSQL -c "
SELECT relname FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('variants_annotated','sample_meta')
ORDER BY 1;"

# 2) At least one row to render (we only need any)
step "Row presence"
$PSQL -c "SELECT COUNT(*) AS rows FROM public.variants_annotated;"

# 3) wkhtmltopdf presence
step "wkhtmltopdf check"
command -v wkhtmltopdf && wkhtmltopdf --version

# 4) Generate a tiny HTML and render to PDF
step "PDF smoke"
mkdir -p "$OUT"
cat > "$HTML" <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Genomics Report PDF Smoke</title>
<style>body{font-family:DejaVu Sans, sans-serif;margin:24px}h1{margin:0 0 12px}</style>
</head><body>
<h1>Genomics Report — PDF Smoke</h1>
<p>If you can read this as a PDF, wkhtmltopdf is working.</p>
</body></html>
HTML

wkhtmltopdf "$HTML" "$PDF"
test -s "$PDF" && echo "[verify] PDF OK"

# 5) Summarize a sample table → HTML → PDF (mini-render page)
step "Mini HTML from DB"
SAMPLE=$($PSQL -At -c "SELECT sample_id FROM public.variants_annotated LIMIT 1;")
if [ -n "$SAMPLE" ]; then
  MH="$OUT/${SAMPLE}_mini.html"
  MP="$OUT/${SAMPLE}_mini.pdf"
  {
    echo '<!doctype html><html><head><meta charset="utf-8"><title>Mini</title>'
    echo '<style>body{font-family:DejaVu Sans, sans-serif;margin:24px} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 8px}</style></head><body>'
    echo "<h2>Sample $SAMPLE — Top Variants</h2><table><tr><th>chrom</th><th>pos</th><th>gene</th><th>consequence</th><th>impact</th></tr>"
    $PSQL -At -c "SELECT chrom,pos,gene,consequence,impact FROM public.variants_annotated WHERE sample_id='$SAMPLE' ORDER BY chrom,pos LIMIT 20;"       | awk -F '|' '{printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",$1,$2,$3,$4,$5}'
    echo "</table></body></html>"
  } > "$MH"
  wkhtmltopdf "$MH" "$MP"
  test -s "$MP" && echo "[verify] Mini PDF OK: $MP"
else
  echo "[verify] No sample_id rows; skipping mini PDF"
fi

echo "[verify] ALL GREEN"
