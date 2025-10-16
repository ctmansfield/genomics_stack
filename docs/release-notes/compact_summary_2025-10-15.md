What: Added public.v_gene_summary view that joins your rollup MVs (GO, Reactome, PubMed, Drug, HPO) for a one-row-per-gene summary. Optional public.mv_gene_summary for speed.

Why: Gives UI and CLI an instant “card” per gene without joining multiple MVs.

Safety: Read-only view; optional MV is add-only with indexes. No env changes.

Install

# from repo root with your venv active (PG* preloaded)
psql -v ON_ERROR_STOP=1 -f sql/summary/001_compact_gene_summary.sql

# optional materialized version
psql -v ON_ERROR_STOP=1 -f sql/summary/010_compact_gene_summary_mv.sql
-- later: REFRESH MATERIALIZED VIEW public.mv_gene_summary;


Verify

chmod +x scripts/verify_compact_summary.sh
./scripts/verify_compact_summary.sh