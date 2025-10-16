-- Materialized flavor with GIN index for fast search.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_gene_search AS
SELECT * FROM public.v_gene_search;

-- Index for fast prefix/contains queries using tsqueries
CREATE INDEX IF NOT EXISTS ix_mv_gene_search_tsv ON public.mv_gene_search USING GIN (search_vector);

-- Also index symbol for exact lookups
CREATE INDEX IF NOT EXISTS ix_mv_gene_search_symbol ON public.mv_gene_search (gene_symbol);
