-- Materialized counts from v2 table.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_hpo_counts_v2 AS
SELECT e.gene_symbol, COUNT(*)::int AS n_hpo
FROM public.gene_to_hpo_v2 e
GROUP BY e.gene_symbol;

CREATE INDEX IF NOT EXISTS ix_mv_hpo_counts_v2_gene ON public.mv_hpo_counts_v2 (gene_symbol);

-- Optional: unique idx to allow CONCURRENT refresh later
-- CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_mv_hpo_counts_v2_gene
--   ON public.mv_hpo_counts_v2 (gene_symbol);
