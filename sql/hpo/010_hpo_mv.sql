-- Counts per gene for UX summary cards
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_hpo_counts AS
SELECT
  e.gene_symbol,
  COUNT(*)::int AS n_hpo
FROM public.gene_to_hpo e
GROUP BY e.gene_symbol;

-- Helpful index (and prerequisite if you later want CONCURRENT refresh)
CREATE INDEX IF NOT EXISTS ix_mv_hpo_counts_gene ON public.mv_hpo_counts (gene_symbol);
