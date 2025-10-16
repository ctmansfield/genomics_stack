#!/usr/bin/env bash
set +e
sym="$1"; [ -z "$sym" ] && { echo "usage: $0 GENE_SYMBOL"; exit 1; }
psql -X -v ON_ERROR_STOP=1 -c "\pset pager off" -c "\x auto" \
  -c "SELECT public.gene_card_json('$sym');"
