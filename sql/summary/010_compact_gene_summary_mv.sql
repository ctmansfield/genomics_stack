-- Optional: materialized flavor for fast UI cards.
-- Create once; refresh on demand or after upstream MV refreshes.

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_gene_summary AS
SELECT * FROM public.v_gene_summary;

-- Helpful index for lookups
CREATE INDEX IF NOT EXISTS ix_mv_gene_summary_symbol ON public.mv_gene_summary (gene_symbol);
