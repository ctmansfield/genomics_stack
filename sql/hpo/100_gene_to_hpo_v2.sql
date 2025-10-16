-- Clean v2 table that avoids legacy hp_id NOT NULL/odd FKs.
CREATE TABLE IF NOT EXISTS public.gene_to_hpo_v2 (
  gene_symbol   text    NOT NULL,
  hpo_id        text    NOT NULL,
  evidence      text,
  source        text,
  evidence_norm text GENERATED ALWAYS AS (
                  NULLIF(lower(regexp_replace(coalesce(evidence,''), '\s+', ' ', 'g')), '')
                ) STORED
);

-- FK to terms (NOT VALID so it won’t block; validate later if desired)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema='public' AND table_name='gene_to_hpo_v2'
      AND constraint_type='FOREIGN KEY' AND constraint_name='fk_gth2_hpo'
  ) THEN
    ALTER TABLE public.gene_to_hpo_v2
      ADD CONSTRAINT fk_gth2_hpo
      FOREIGN KEY (hpo_id) REFERENCES public.hpo_terms(hpo_id) ON DELETE RESTRICT NOT VALID;
  END IF;
END$$;

-- Indexes + unique constraint for fast dedupe/upsert patterns
CREATE INDEX IF NOT EXISTS ix_gth2_gene ON public.gene_to_hpo_v2 (gene_symbol);
CREATE INDEX IF NOT EXISTS ix_gth2_hpo  ON public.gene_to_hpo_v2 (hpo_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema='public' AND table_name='gene_to_hpo_v2'
      AND constraint_type='UNIQUE' AND constraint_name='uq_gth2_gene_hpo_ev'
  ) THEN
    ALTER TABLE public.gene_to_hpo_v2
      ADD CONSTRAINT uq_gth2_gene_hpo_ev UNIQUE (gene_symbol, hpo_id, evidence_norm);
  END IF;
END$$;
