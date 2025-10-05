--
-- PostgreSQL database dump
--

\restrict tbjnrTY93bzKw79pEdRBVqqCVxfChDu0AgFOGXmHswQYxDEfkuI2gKj0kwV8kf6

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Ubuntu 16.10-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: infer_zygosity(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.infer_zygosity(gt text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$DECLARE
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
END;$_$;


--
-- Name: risk_hits_recalc(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.risk_hits_recalc(p_upload_id bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$DECLARE
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
END;$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: all_variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.all_variants (
    rsid text NOT NULL
);


--
-- Name: gene_pairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gene_pairs (
    pair_id integer NOT NULL,
    gene_id_a integer NOT NULL,
    gene_id_b integer NOT NULL,
    link_type text DEFAULT 'functional'::text,
    note text,
    pair_lo integer GENERATED ALWAYS AS (LEAST(gene_id_a, gene_id_b)) STORED,
    pair_hi integer GENERATED ALWAYS AS (GREATEST(gene_id_a, gene_id_b)) STORED,
    CONSTRAINT gp_distinct CHECK ((gene_id_a <> gene_id_b))
);


--
-- Name: genes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.genes (
    gene_id integer NOT NULL,
    symbol text NOT NULL,
    name text
);


--
-- Name: gene_pairs_named; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.gene_pairs_named AS
 SELECT gp.pair_id,
    gp.link_type,
    gp.note,
    ga.gene_id AS gene_id_a,
    ga.symbol AS symbol_a,
    gb.gene_id AS gene_id_b,
    gb.symbol AS symbol_b
   FROM ((public.gene_pairs gp
     JOIN public.genes ga ON ((ga.gene_id = gp.gene_id_a)))
     JOIN public.genes gb ON ((gb.gene_id = gp.gene_id_b)));


--
-- Name: gene_pairs_pair_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gene_pairs_pair_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gene_pairs_pair_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gene_pairs_pair_id_seq OWNED BY public.gene_pairs.pair_id;


--
-- Name: genes_gene_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.genes_gene_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: genes_gene_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.genes_gene_id_seq OWNED BY public.genes.gene_id;


--
-- Name: healthcheck; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.healthcheck (
    id integer NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: healthcheck_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.healthcheck_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: healthcheck_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.healthcheck_id_seq OWNED BY public.healthcheck.id;


--
-- Name: processed; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed (
    rsid text NOT NULL
);


--
-- Name: risk_hits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risk_hits (
    upload_id bigint NOT NULL,
    rule_id integer NOT NULL,
    zygosity text,
    score numeric NOT NULL,
    CONSTRAINT risk_hits_zygosity_check CHECK ((zygosity = ANY (ARRAY['het'::text, 'hom'::text, 'ref'::text])))
);


--
-- Name: risk_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risk_rules (
    rule_id integer NOT NULL,
    gene_id integer NOT NULL,
    variant_id integer,
    zygosity_required text DEFAULT 'any'::text,
    weight numeric NOT NULL,
    short_title text NOT NULL,
    impact_blurb text NOT NULL,
    nutrition_note text,
    evidence_notes text,
    is_active boolean DEFAULT true,
    system_tag text DEFAULT 'General'::text NOT NULL,
    CONSTRAINT risk_rules_zygosity_required_check CHECK ((zygosity_required = ANY (ARRAY['het'::text, 'hom'::text, 'any'::text])))
);


--
-- Name: risk_rules_rule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.risk_rules_rule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: risk_rules_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.risk_rules_rule_id_seq OWNED BY public.risk_rules.rule_id;


--
-- Name: sample_meta; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sample_meta AS
 SELECT sample_id,
    subject_id,
    cohort,
    meta
   FROM risk_test.sample_meta;


--
-- Name: shard_manifest; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shard_manifest (
    shard_id integer NOT NULL,
    csv_path text,
    vep_input_path text,
    variant_count integer,
    status text,
    notes text
);


--
-- Name: staging_array_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staging_array_calls (
    upload_id bigint NOT NULL,
    chrom text,
    pos bigint,
    allele1 text,
    allele2 text,
    rsid text,
    genotype text,
    zygosity text,
    call text
);


--
-- Name: unscored; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unscored (
    rsid text NOT NULL
);


--
-- Name: variant_pairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variant_pairs (
    vpair_id integer NOT NULL,
    variant_id_a integer NOT NULL,
    variant_id_b integer NOT NULL,
    link_type text DEFAULT 'clinical_combo'::text,
    note text,
    vpair_lo integer GENERATED ALWAYS AS (LEAST(variant_id_a, variant_id_b)) STORED,
    vpair_hi integer GENERATED ALWAYS AS (GREATEST(variant_id_a, variant_id_b)) STORED,
    CONSTRAINT vp_distinct CHECK ((variant_id_a <> variant_id_b))
);


--
-- Name: variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variants (
    variant_id integer NOT NULL,
    chrom text NOT NULL,
    pos bigint NOT NULL,
    ref text NOT NULL,
    alt text NOT NULL,
    rsid text,
    gene_id integer
);


--
-- Name: variant_pairs_named; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.variant_pairs_named AS
 SELECT vp.vpair_id,
    vp.link_type,
    vp.note,
    va.variant_id AS variant_id_a,
    va.rsid AS rsid_a,
    vb.variant_id AS variant_id_b,
    vb.rsid AS rsid_b
   FROM ((public.variant_pairs vp
     JOIN public.variants va ON ((va.variant_id = vp.variant_id_a)))
     JOIN public.variants vb ON ((vb.variant_id = vp.variant_id_b)));


--
-- Name: variant_pairs_vpair_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.variant_pairs_vpair_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: variant_pairs_vpair_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.variant_pairs_vpair_id_seq OWNED BY public.variant_pairs.vpair_id;


--
-- Name: variants_annotated; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.variants_annotated AS
 SELECT sample_id,
    chrom,
    pos,
    ref,
    alt,
    consequence,
    gene,
    impact,
    clin_sig,
    af,
    af_pop,
    vep_json
   FROM risk_test.variants_annotated;


--
-- Name: variants_variant_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.variants_variant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: variants_variant_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.variants_variant_id_seq OWNED BY public.variants.variant_id;


--
-- Name: gene_pairs pair_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gene_pairs ALTER COLUMN pair_id SET DEFAULT nextval('public.gene_pairs_pair_id_seq'::regclass);


--
-- Name: genes gene_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genes ALTER COLUMN gene_id SET DEFAULT nextval('public.genes_gene_id_seq'::regclass);


--
-- Name: healthcheck id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.healthcheck ALTER COLUMN id SET DEFAULT nextval('public.healthcheck_id_seq'::regclass);


--
-- Name: risk_rules rule_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_rules ALTER COLUMN rule_id SET DEFAULT nextval('public.risk_rules_rule_id_seq'::regclass);


--
-- Name: variant_pairs vpair_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variant_pairs ALTER COLUMN vpair_id SET DEFAULT nextval('public.variant_pairs_vpair_id_seq'::regclass);


--
-- Name: variants variant_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variants ALTER COLUMN variant_id SET DEFAULT nextval('public.variants_variant_id_seq'::regclass);


--
-- Name: all_variants all_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.all_variants
    ADD CONSTRAINT all_variants_pkey PRIMARY KEY (rsid);


--
-- Name: gene_pairs gene_pairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gene_pairs
    ADD CONSTRAINT gene_pairs_pkey PRIMARY KEY (pair_id);


--
-- Name: genes genes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genes
    ADD CONSTRAINT genes_pkey PRIMARY KEY (gene_id);


--
-- Name: genes genes_symbol_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genes
    ADD CONSTRAINT genes_symbol_key UNIQUE (symbol);


--
-- Name: healthcheck healthcheck_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.healthcheck
    ADD CONSTRAINT healthcheck_pkey PRIMARY KEY (id);


--
-- Name: processed processed_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed
    ADD CONSTRAINT processed_pkey PRIMARY KEY (rsid);


--
-- Name: risk_hits risk_hits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_hits
    ADD CONSTRAINT risk_hits_pkey PRIMARY KEY (upload_id, rule_id);


--
-- Name: risk_rules risk_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_rules
    ADD CONSTRAINT risk_rules_pkey PRIMARY KEY (rule_id);


--
-- Name: shard_manifest shard_manifest_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shard_manifest
    ADD CONSTRAINT shard_manifest_pkey PRIMARY KEY (shard_id);


--
-- Name: unscored unscored_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unscored
    ADD CONSTRAINT unscored_pkey PRIMARY KEY (rsid);


--
-- Name: variant_pairs variant_pairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variant_pairs
    ADD CONSTRAINT variant_pairs_pkey PRIMARY KEY (vpair_id);


--
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (variant_id);


--
-- Name: idx_risk_hits_upload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_risk_hits_upload ON public.risk_hits USING btree (upload_id);


--
-- Name: idx_risk_rules_gene; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_risk_rules_gene ON public.risk_rules USING btree (gene_id);


--
-- Name: idx_risk_rules_system; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_risk_rules_system ON public.risk_rules USING btree (system_tag);


--
-- Name: idx_risk_rules_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_risk_rules_variant ON public.risk_rules USING btree (variant_id);


--
-- Name: idx_variants_rsid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_variants_rsid ON public.variants USING btree (rsid);


--
-- Name: uq_gene_pairs_set; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_gene_pairs_set ON public.gene_pairs USING btree (pair_lo, pair_hi);


--
-- Name: uq_risk_rules_def_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_risk_rules_def_idx ON public.risk_rules USING btree (gene_id, variant_id, short_title);


--
-- Name: uq_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_variant ON public.variants USING btree (chrom, pos, ref, alt);


--
-- Name: uq_variant_pairs_set; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_variant_pairs_set ON public.variant_pairs USING btree (vpair_lo, vpair_hi);


--
-- Name: gene_pairs gene_pairs_gene_id_a_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gene_pairs
    ADD CONSTRAINT gene_pairs_gene_id_a_fkey FOREIGN KEY (gene_id_a) REFERENCES public.genes(gene_id);


--
-- Name: gene_pairs gene_pairs_gene_id_b_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gene_pairs
    ADD CONSTRAINT gene_pairs_gene_id_b_fkey FOREIGN KEY (gene_id_b) REFERENCES public.genes(gene_id);


--
-- Name: risk_hits risk_hits_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_hits
    ADD CONSTRAINT risk_hits_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.risk_rules(rule_id);


--
-- Name: risk_rules risk_rules_gene_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_rules
    ADD CONSTRAINT risk_rules_gene_id_fkey FOREIGN KEY (gene_id) REFERENCES public.genes(gene_id);


--
-- Name: risk_rules risk_rules_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risk_rules
    ADD CONSTRAINT risk_rules_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(variant_id);


--
-- Name: variant_pairs variant_pairs_variant_id_a_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variant_pairs
    ADD CONSTRAINT variant_pairs_variant_id_a_fkey FOREIGN KEY (variant_id_a) REFERENCES public.variants(variant_id);


--
-- Name: variant_pairs variant_pairs_variant_id_b_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variant_pairs
    ADD CONSTRAINT variant_pairs_variant_id_b_fkey FOREIGN KEY (variant_id_b) REFERENCES public.variants(variant_id);


--
-- Name: variants variants_gene_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_gene_id_fkey FOREIGN KEY (gene_id) REFERENCES public.genes(gene_id);


--
-- PostgreSQL database dump complete
--

\unrestrict tbjnrTY93bzKw79pEdRBVqqCVxfChDu0AgFOGXmHswQYxDEfkuI2gKj0kwV8kf6

