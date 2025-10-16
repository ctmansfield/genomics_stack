-- HPO core objects (owned tables). Uses the project's preferred patterns.

-- 1) Terms dictionary (dedup on hpo_id)
CREATE TABLE IF NOT EXISTS public.hpo_terms (
  hpo_id   text PRIMARY KEY,         -- 'HP:nnnnnnn'
  label    text NOT NULL
);

-- 2) Gene ↔ HPO edges (normalized)
--    evidence_norm is generated for uniqueness and dedupe stability.
CREATE TABLE IF NOT EXISTS public.gene_to_hpo (
  gene_symbol     text NOT NULL,
  hpo_id          text NOT NULL REFERENCES public.hpo_terms(hpo_id) ON DELETE RESTRICT,
  evidence        text,
  source          text,
  evidence_norm   text GENERATED ALWAYS AS (
                    NULLIF(lower(regexp_replace(coalesce(evidence,''), '\s+', ' ', 'g')), '')
                  ) STORED,
  CONSTRAINT uq_gene_hpo UNIQUE (gene_symbol, hpo_id, evidence_norm)
);

-- Indexes to support common queries
CREATE INDEX IF NOT EXISTS ix_gene_to_hpo_gene ON public.gene_to_hpo (gene_symbol);
CREATE INDEX IF NOT EXISTS ix_gene_to_hpo_hpo  ON public.gene_to_hpo (hpo_id);
