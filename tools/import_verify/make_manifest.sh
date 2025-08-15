#!/usr/bin/env bash
set -euo pipefail
usage() { echo "usage: $0 /path/to/input.tsv[.gz|.bgz] [header=true|false]"; }
if [[ $# -lt 1 ]]; then usage; exit 1; fi
file="$1"; has_header="${2:-true}"
[[ -f "$file" ]] || { echo "[ERR] file not found: $file"; exit 1; }
case "$has_header" in true|false) : ;; *) echo "[ERR] header must be true|false"; exit 1;; esac
if [[ "$file" =~ \.gz$|\.bgz$ ]]; then
  if command -v bgzip >/dev/null 2>&1; then bgzip -t "$file"; else gzip -t "$file"; fi
  n_lines=$(zcat "$file" | wc -l)
else
  n_lines=$(wc -l < "$file")
fi
expected_rows="$n_lines"
[[ "$has_header" == "true" ]] && expected_rows=$((n_lines-1))
sha256=$(sha256sum "$file" | awk '{print $1}')
manifest="${file}.manifest.json"
cat > "$manifest" <<JSON
{
  "file": "$(basename "$file")",
  "expected_rows": $expected_rows,
  "sha256": "$sha256",
  "has_header": $has_header
}
JSON
echo "[OK] Wrote $manifest"
echo "[OK] expected_rows=$expected_rows sha256=$sha256"
