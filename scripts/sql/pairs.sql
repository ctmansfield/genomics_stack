BEGIN;

CREATE TABLE IF NOT EXISTS public.gene_pairs (
  pair_id   serial PRIMARY KEY,
  gene_id_a int NOT NULL REFERENCES public.genes(gene_id),
  gene_id_b int NOT NULL REFERENCES public.genes(gene_id),
  link_type text DEFAULT 'functional',
  note      text,
  CONSTRAINT gp_distinct CHECK (gene_id_a <> gene_id_b)
);

CREATE TABLE IF NOT EXISTS public.variant_pairs (
  vpair_id     serial PRIMARY KEY,
  variant_id_a int NOT NULL REFERENCES public.variants(variant_id),
  variant_id_b int NOT NULL REFERENCES public.variants(variant_id),
  link_type    text DEFAULT 'clinical_combo',
  note         text,
  CONSTRAINT vp_distinct CHECK (variant_id_a <> variant_id_b)
);

-- normalized generated columns for stable uniqueness
ALTER TABLE public.gene_pairs
  ADD COLUMN IF NOT EXISTS pair_lo int GENERATED ALWAYS AS (LEAST(gene_id_a,gene_id_b)) STORED,
  ADD COLUMN IF NOT EXISTS pair_hi int GENERATED ALWAYS AS (GREATEST(gene_id_a,gene_id_b)) STORED;

ALTER TABLE public.variant_pairs
  ADD COLUMN IF NOT EXISTS vpair_lo int GENERATED ALWAYS AS (LEAST(variant_id_a,variant_id_b)) STORED,
  ADD COLUMN IF NOT EXISTS vpair_hi int GENERATED ALWAYS AS (GREATEST(variant_id_a,variant_id_b)) STORED;

-- unique indexes if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_gene_pairs_set') THEN
    EXECUTE 'CREATE UNIQUE INDEX uq_gene_pairs_set ON public.gene_pairs(pair_lo, pair_hi)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_variant_pairs_set') THEN
    EXECUTE 'CREATE UNIQUE INDEX uq_variant_pairs_set ON public.variant_pairs(vpair_lo, vpair_hi)';
  END IF;
END$$;

-- helper views
CREATE OR REPLACE VIEW public.gene_pairs_named AS
SELECT
  gp.pair_id, gp.link_type, gp.note,
  ga.gene_id AS gene_id_a, ga.symbol AS symbol_a,
  gb.gene_id AS gene_id_b, gb.symbol AS symbol_b
FROM public.gene_pairs gp
JOIN public.genes ga ON ga.gene_id = gp.gene_id_a
JOIN public.genes gb ON gb.gene_id = gp.gene_id_b;

CREATE OR REPLACE VIEW public.variant_pairs_named AS
SELECT
  vp.vpair_id, vp.link_type, vp.note,
  va.variant_id AS variant_id_a, va.rsid AS rsid_a,
  vb.variant_id AS variant_id_b, vb.rsid AS rsid_b
FROM public.variant_pairs vp
JOIN public.variants va ON va.variant_id = vp.variant_id_a
JOIN public.variants vb ON vb.variant_id = vp.variant_id_b;

COMMIT;
