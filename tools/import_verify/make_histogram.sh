#!/usr/bin/env bash
set -euo pipefail
file="${1:?path to tsv}"; col="${2:-1}"; has_header="${3:-true}"
[[ -f "$file" ]] || { echo "[ERR] file not found: $file"; exit 1; }
case "$has_header" in true|false) : ;; *) echo "[ERR] has_header must be true|false"; exit 1;; esac
if [[ "$file" =~ \.gz$|\.bgz$ ]]; then src=(zcat "$file"); else src=(cat "$file"); fi
out="${file}.by_chrom.txt"
if [[ "$has_header" == "true" ]]; then
  "${src[@]}" | awk -F'\t' -v c="$col" 'NR>1 {h[$c]++} END{for (k in h) print k"\t"h[k]}' | sort -k1,1 > "$out"
else
  "${src[@]}" | awk -F'\t' -v c="$col" '{h[$c]++} END{for (k in h) print k"\t"h[k]}' | sort -k1,1 > "$out"
fi
echo "[OK] Wrote $out"
