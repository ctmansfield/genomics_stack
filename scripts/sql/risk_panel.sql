BEGIN;

CREATE TABLE IF NOT EXISTS public.genes (
  gene_id serial PRIMARY KEY,
  symbol  text UNIQUE NOT NULL,
  name    text
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='variants' AND column_name='gene_id'
  ) THEN
    EXECUTE 'ALTER TABLE public.variants ADD COLUMN gene_id int';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='variants_gene_id_fkey') THEN
    EXECUTE 'ALTER TABLE public.variants
             ADD CONSTRAINT variants_gene_id_fkey
             FOREIGN KEY (gene_id) REFERENCES public.genes(gene_id)';
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.risk_rules (
  rule_id serial PRIMARY KEY,
  gene_id int NOT NULL REFERENCES public.genes(gene_id),
  variant_id int REFERENCES public.variants(variant_id),
  zygosity_required text DEFAULT 'any' CHECK (zygosity_required IN ('het','hom','any')),
  weight numeric NOT NULL,
  short_title text NOT NULL,
  impact_blurb text NOT NULL,
  nutrition_note text,
  evidence_notes text,
  is_active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.risk_hits (
  upload_id bigint NOT NULL,
  rule_id int NOT NULL REFERENCES public.risk_rules(rule_id),
  zygosity text CHECK (zygosity IN ('het','hom','ref')),
  score numeric NOT NULL,
  PRIMARY KEY (upload_id, rule_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.risk_rules'::regclass
      AND conname='uq_risk_rules_def'
  ) THEN
    EXECUTE 'ALTER TABLE public.risk_rules
             ADD CONSTRAINT uq_risk_rules_def
             UNIQUE (gene_id, variant_id, short_title)';
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_variants_gene_id   ON public.variants(gene_id);
CREATE INDEX IF NOT EXISTS idx_variants_rsid      ON public.variants(rsid);
CREATE INDEX IF NOT EXISTS idx_risk_rules_gene    ON public.risk_rules(gene_id);
CREATE INDEX IF NOT EXISTS idx_risk_rules_variant ON public.risk_rules(variant_id);
CREATE INDEX IF NOT EXISTS idx_risk_hits_upload   ON public.risk_hits(upload_id);

COMMIT;
