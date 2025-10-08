-- ClinPGx core schema (PharmGKB + CPIC scaffolding)
-- Safe to run multiple times.

CREATE TABLE IF NOT EXISTS public.drug_catalog (
  drug_id         bigserial PRIMARY KEY,
  preferred_name  text NOT NULL,
  atc_code        text,
  rxnorm_id       text,
  synonyms        text[],
  created_at      timestamptz DEFAULT now()
);
DO $$ BEGIN
  CREATE UNIQUE INDEX uq_drug_name ON public.drug_catalog (lower(preferred_name));
EXCEPTION WHEN duplicate_table THEN NULL; END $$;

-- NOTE: assumes public.gene_catalog(gene_symbol) already exists.

CREATE TABLE IF NOT EXISTS public.gene_drug_guidelines (
  row_id         bigserial PRIMARY KEY,
  source         text NOT NULL,         -- 'CPIC'|'PharmGKB'|'DPWG'...
  source_key     text,
  gene_symbol    text NOT NULL REFERENCES public.gene_catalog(gene_symbol),
  drug_id        bigint NOT NULL REFERENCES public.drug_catalog(drug_id),
  level          text,
  phenotype      text,
  recommendation text,
  strength       text,
  url            text,
  last_reviewed  date,
  created_at     timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gdg_gene ON public.gene_drug_guidelines(gene_symbol);
CREATE INDEX IF NOT EXISTS idx_gdg_drug ON public.gene_drug_guidelines(drug_id);

CREATE TABLE IF NOT EXISTS public.pgx_allele_definitions (
  gene_symbol      text NOT NULL REFERENCES public.gene_catalog(gene_symbol),
  star_allele      text NOT NULL,
  function         text,
  defining_variants text[],
  requires_cnv     bool DEFAULT false,
  requires_phasing bool DEFAULT false,
  PRIMARY KEY (gene_symbol, star_allele)
);

CREATE TABLE IF NOT EXISTS public.pgx_diplotype_phenotype (
  gene_symbol   text NOT NULL,
  diplotype     text NOT NULL,
  phenotype     text NOT NULL,
  activity_score numeric,
  cpic_strength  text,
  PRIMARY KEY (gene_symbol, diplotype)
);

CREATE TABLE IF NOT EXISTS public.pgx_pheno_recommendations (
  gene_symbol   text NOT NULL,
  drug_id       bigint NOT NULL REFERENCES public.drug_catalog(drug_id),
  phenotype     text NOT NULL,
  recommendation text NOT NULL,
  strength       text,
  url            text,
  PRIMARY KEY (gene_symbol, drug_id, phenotype)
);

CREATE TABLE IF NOT EXISTS public.pgx_drug_labels (
  row_id     bigserial PRIMARY KEY,
  agency     text,
  drug_id    bigint NOT NULL REFERENCES public.drug_catalog(drug_id),
  biomarker  text,
  label_flag text,
  url        text
);
-- helper for fast idempotent upsert lookups
CREATE INDEX IF NOT EXISTS idx_pgx_labels_key ON public.pgx_drug_labels(agency, drug_id, url);

-- bridge to evidence_items (assumes evidence_items exists)
CREATE TABLE IF NOT EXISTS public.evidence_pgx_drug_labels (
  row_id     bigint NOT NULL REFERENCES public.pgx_drug_labels(row_id) ON DELETE CASCADE,
  evidence_id bigint NOT NULL REFERENCES public.evidence_items(evidence_id) ON DELETE CASCADE,
  PRIMARY KEY (row_id, evidence_id)
);
