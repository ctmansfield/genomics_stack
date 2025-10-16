-- Unique index to allow CONCURRENT refresh on mv_hpo_counts
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_mv_hpo_counts_gene
  ON public.mv_hpo_counts(gene_symbol);
