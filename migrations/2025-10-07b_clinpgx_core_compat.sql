-- ClinPGx core schema (compat): create tables without hard FKs so non-owner roles can run it.
-- If privileges permit, add FKs inside try/catch blocks.

SET search_path TO public, genomics;

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

-- No FK here to avoid permission errors when gene_catalog is owned by another role/schema.
CREATE TABLE IF NOT EXISTS public.gene_drug_guidelines (
  row_id         bigserial PRIMARY KEY,
  source         text NOT NULL,
  source_key     text,
  gene_symbol    text NOT NULL,        -- reference to gene_catalog.gene_symbol (soft)
  drug_id        bigint NOT NULL,      -- reference to drug_catalog.drug_id (we own this)
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

-- Soft references to gene catalog (no FK)
CREATE TABLE IF NOT EXISTS public.pgx_allele_definitions (
  gene_symbol       text NOT NULL,
  star_allele       text NOT NULL,
  function          text,
  defining_variants text[],
  requires_cnv      bool DEFAULT false,
  requires_phasing  bool DEFAULT false,
  PRIMARY KEY (gene_symbol, star_allele)
);

CREATE TABLE IF NOT EXISTS public.pgx_diplotype_phenotype (
  gene_symbol    text NOT NULL,
  diplotype      text NOT NULL,
  phenotype      text NOT NULL,
  activity_score numeric,
  cpic_strength  text,
  PRIMARY KEY (gene_symbol, diplotype)
);

CREATE TABLE IF NOT EXISTS public.pgx_pheno_recommendations (
  gene_symbol    text NOT NULL,
  drug_id        bigint NOT NULL,
  phenotype      text NOT NULL,
  recommendation text NOT NULL,
  strength       text,
  url            text,
  PRIMARY KEY (gene_symbol, drug_id, phenotype)
);

CREATE TABLE IF NOT EXISTS public.pgx_drug_labels (
  row_id     bigserial PRIMARY KEY,
  agency     text,
  drug_id    bigint NOT NULL,
  biomarker  text,
  label_flag text,
  url        text
);
CREATE INDEX IF NOT EXISTS idx_pgx_labels_key ON public.pgx_drug_labels(agency, drug_id, url);

-- Evidence bridge: create without FKs, then try to attach them if permitted
CREATE TABLE IF NOT EXISTS public.evidence_pgx_drug_labels (
  row_id      bigint NOT NULL,
  evidence_id bigint NOT NULL,
  PRIMARY KEY (row_id, evidence_id)
);

-- Best-effort FK to our own table (we own pgx_drug_labels)
DO $$ BEGIN
  ALTER TABLE public.evidence_pgx_drug_labels
    ADD CONSTRAINT fk_epdl_label
    FOREIGN KEY (row_id) REFERENCES public.pgx_drug_labels(row_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN
  NULL;
WHEN insufficient_privilege THEN
  NULL;
WHEN undefined_table THEN
  NULL;
END $$;

-- Best-effort FK to evidence_items if caller has rights and table exists
DO $$ BEGIN
  PERFORM 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='evidence_items';
  IF FOUND THEN
    BEGIN
      ALTER TABLE public.evidence_pgx_drug_labels
        ADD CONSTRAINT fk_epdl_evidence
        FOREIGN KEY (evidence_id) REFERENCES public.evidence_items(evidence_id) ON DELETE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL;
    WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
END $$;
