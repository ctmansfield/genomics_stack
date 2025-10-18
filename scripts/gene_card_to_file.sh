#!/usr/bin/env bash
set -euo pipefail
sym="${1:?usage: $0 GENE_SYMBOL}"; out="${2:-/tmp/${sym}_card.json}"
psql -XAt -c "SELECT public.gene_card_json('${sym}');" > "$out"
echo "[OK] wrote $out"
