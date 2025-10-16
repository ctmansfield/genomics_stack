#!/usr/bin/env bash
: "${PGHOST:=localhost}"
: "${PGUSER:=genouser}"
: "${PGDATABASE:=genome_db}"
: "${PGPORT:=55432}"

echo "[INFO] Refreshing MVs (non-concurrent)"
psql -v ON_ERROR_STOP=1 <<'SQL'
REFRESH MATERIALIZED VIEW public.mv_go_counts;
REFRESH MATERIALIZED VIEW public.mv_pathway_counts;
REFRESH MATERIALIZED VIEW public.mv_pubmed_counts;
REFRESH MATERIALIZED VIEW public.mv_drug_counts;
REFRESH MATERIALIZED VIEW public.mv_gene_drug_counts;
REFRESH MATERIALIZED VIEW public.mv_hpo_counts;
SQL
