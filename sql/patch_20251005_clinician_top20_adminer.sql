-- Adminer-friendly SQL (no global transaction). Safe to paste and run.
-- Creates minimal prerequisites if missing, then adds clinician Top 20 support.

-- 0) Core tables (create if missing)
CREATE TABLE IF NOT EXISTS public.genes (
  gene_id serial PRIMARY KEY,
  symbol  text UNIQUE NOT NULL,
  name    text
);

-- Minimal variants table if not present (columns commonly used across repo)
CREATE TABLE IF NOT EXISTS public.variants (
  variant_id serial PRIMARY KEY,
  chrom      text NOT NULL,
  pos        bigint NOT NULL,
  ref        text NOT NULL,
  alt        text NOT NULL,
  rsid       text
);

-- Unique tuple for locus identity (aligns with expected uq_variant usage)
CREATE UNIQUE INDEX IF NOT EXISTS uq_variant ON public.variants(chrom,pos,ref,alt);
CREATE INDEX IF NOT EXISTS idx_variants_rsid ON public.variants(rsid);

-- 1) Augment variants with gene_id FK to genes (idempotent)
ALTER TABLE IF EXISTS public.variants ADD COLUMN IF NOT EXISTS gene_id int;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='variants_gene_id_fkey'
  ) THEN
    EXECUTE 'ALTER TABLE public.variants
             ADD CONSTRAINT variants_gene_id_fkey
             FOREIGN KEY (gene_id) REFERENCES public.genes(gene_id)';
  END IF;
END $$;

-- 2) Risk panel entities
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

-- Unique rule identity (use unique index when constraint may not exist)
CREATE UNIQUE INDEX IF NOT EXISTS uq_risk_rules_def_idx
  ON public.risk_rules(gene_id, variant_id, short_title);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_risk_rules_gene    ON public.risk_rules(gene_id);
CREATE INDEX IF NOT EXISTS idx_risk_rules_variant ON public.risk_rules(variant_id);
CREATE INDEX IF NOT EXISTS idx_risk_hits_upload   ON public.risk_hits(upload_id);

-- 3) System tagging for clinician grouping
ALTER TABLE public.risk_rules ADD COLUMN IF NOT EXISTS system_tag text;
UPDATE public.risk_rules SET system_tag='General' WHERE system_tag IS NULL;
ALTER TABLE public.risk_rules ALTER COLUMN system_tag SET DEFAULT 'General';
ALTER TABLE public.risk_rules ALTER COLUMN system_tag SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_risk_rules_system ON public.risk_rules(system_tag);

-- 4) Pair-awareness structures
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

ALTER TABLE public.gene_pairs
  ADD COLUMN IF NOT EXISTS pair_lo int GENERATED ALWAYS AS (LEAST(gene_id_a,gene_id_b)) STORED;
ALTER TABLE public.gene_pairs
  ADD COLUMN IF NOT EXISTS pair_hi int GENERATED ALWAYS AS (GREATEST(gene_id_a,gene_id_b)) STORED;

ALTER TABLE public.variant_pairs
  ADD COLUMN IF NOT EXISTS vpair_lo int GENERATED ALWAYS AS (LEAST(variant_id_a,variant_id_b)) STORED;
ALTER TABLE public.variant_pairs
  ADD COLUMN IF NOT EXISTS vpair_hi int GENERATED ALWAYS AS (GREATEST(variant_id_a,variant_id_b)) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS uq_gene_pairs_set    ON public.gene_pairs(pair_lo, pair_hi);
CREATE UNIQUE INDEX IF NOT EXISTS uq_variant_pairs_set ON public.variant_pairs(vpair_lo, vpair_hi);

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

-- 5) Helper schema and functions (used by report SQL)
CREATE SCHEMA IF NOT EXISTS anno;

CREATE OR REPLACE FUNCTION anno.vep_impact_rank(impact text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE UPPER(COALESCE($1,''))
           WHEN 'HIGH' THEN 4
           WHEN 'MODERATE' THEN 3
           WHEN 'LOW' THEN 2
           WHEN 'MODIFIER' THEN 1
           ELSE 0
         END
$$;

CREATE OR REPLACE FUNCTION anno.first_rsid(existing_variation text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  t text := COALESCE(existing_variation,'');
  a text[];
BEGIN
  IF t = '' THEN RETURN NULL; END IF;
  a := regexp_match(t, '(rs[0-9]+)');
  IF a IS NULL OR array_length(a,1) IS NULL THEN RETURN NULL; END IF;
  RETURN a[1];
END;
$$;

CREATE OR REPLACE FUNCTION public.infer_zygosity(gt text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s  text := lower(coalesce(gt,''));
  a1 text;
  a2 text;
BEGIN
  IF s = '' THEN RETURN NULL; END IF;
  IF s IN ('het','hom','ref') THEN RETURN s; END IF;
  IF s ~ '^[01][/|][01]$' THEN
    IF substring(s,1,1) = substring(s,3,1) THEN
      IF substring(s,1,1) = '1' THEN RETURN 'hom'; ELSE RETURN 'ref'; END IF;
    ELSE
      RETURN 'het';
    END IF;
  END IF;
  IF s ~ '^[acgt][/|][acgt]$' THEN
    a1 := substring(s,1,1);
    a2 := substring(s,3,1);
    IF a1 = a2 THEN RETURN 'hom'; ELSE RETURN 'het'; END IF;
  END IF;
  IF s ~ '^[acgt]{2}$' THEN
    a1 := substring(s,1,1);
    a2 := substring(s,2,1);
    IF a1 = a2 THEN RETURN 'hom'; ELSE RETURN 'het'; END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.risk_hits_recalc(p_upload_id bigint)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  rows int := 0;
BEGIN
  DELETE FROM public.risk_hits WHERE upload_id = p_upload_id;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='genotypes') AND
     EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='genotypes' AND column_name='upload_id') AND
     EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='genotypes' AND column_name='variant_id')
  THEN
    INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
    SELECT p_upload_id,
           r.rule_id,
           z AS zygosity,
           CASE z WHEN 'hom' THEN r.weight*2.0
                  WHEN 'het' THEN r.weight*1.0
                  ELSE 0::numeric END AS score
    FROM public.risk_rules r
    JOIN (
      SELECT g.variant_id,
             public.infer_zygosity(
               COALESCE(
                 (SELECT g.zygosity  WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='zygosity')),
                 (SELECT g.gt        WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='gt')),
                 (SELECT g.genotype  WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='genotype')),
                 (SELECT g.call      WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='call'))
               )
             ) AS z
      FROM public.genotypes g
      WHERE g.upload_id = p_upload_id
    ) g ON g.variant_id = r.variant_id
    WHERE r.is_active AND g.z IN ('het','hom');

    GET DIAGNOSTICS rows = ROW_COUNT;
    IF rows > 0 THEN RETURN rows; END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='staging_array_calls') THEN

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='rsid') THEN
      INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
      SELECT p_upload_id, r.rule_id, z AS zygosity,
             CASE z WHEN 'hom' THEN r.weight*2.0
                    WHEN 'het' THEN r.weight*1.0
                    ELSE 0::numeric END
      FROM public.risk_rules r
      JOIN public.variants v ON v.variant_id = r.variant_id
      JOIN (
        SELECT s.rsid,
               public.infer_zygosity(
                 COALESCE(
                   (SELECT s.zygosity WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='zygosity')),
                   (SELECT s.genotype WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='genotype')),
                   (SELECT s.call     WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='call'))
                 )
               ) AS z
        FROM public.staging_array_calls s
        WHERE s.upload_id = p_upload_id
      ) s ON s.rsid = v.rsid
      WHERE r.is_active AND s.z IN ('het','hom');

      GET DIAGNOSTICS rows = ROW_COUNT;
      IF rows > 0 THEN RETURN rows; END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='chrom') AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='pos')   AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='ref')   AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='alt')
    THEN
      INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
      SELECT p_upload_id, r.rule_id, z AS zygosity,
             CASE z WHEN 'hom' THEN r.weight*2.0
                    WHEN 'het' THEN r.weight*1.0
                    ELSE 0::numeric END
      FROM public.risk_rules r
      JOIN public.variants v ON v.variant_id = r.variant_id
      JOIN (
        SELECT s.chrom, s.pos, s.ref, s.alt,
               public.infer_zygosity(
                 COALESCE(
                   (SELECT s.zygosity WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='zygosity')),
                   (SELECT s.genotype WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='genotype')),
                   (SELECT s.call     WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='call'))
                 )
               ) AS z
        FROM public.staging_array_calls s
        WHERE s.upload_id = p_upload_id
      ) s ON s.chrom=v.chrom AND s.pos=v.pos AND s.ref=v.ref AND s.alt=v.alt
      WHERE r.is_active AND s.z IN ('het','hom');

      GET DIAGNOSTICS rows = ROW_COUNT;
      IF rows > 0 THEN RETURN rows; END IF;
    END IF;
  END IF;

  RETURN rows;
END;
$$;
