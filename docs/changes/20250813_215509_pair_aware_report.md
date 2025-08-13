# Pair-aware Top-N report & pair schema

- Add `public.gene_pairs`, `public.variant_pairs` with stable UNIQUE constraints
- Create `gene_pairs_named`, `variant_pairs_named`
- Update `report_top.sh`: risk-first, VEP fallback, pair clustering, `paired_with` column
- SQL applied via stdin to avoid container path issues

Deployed: 2025-08-13T21:55:09+00:00
