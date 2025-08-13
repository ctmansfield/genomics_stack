--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9 (Debian 16.9-1.pgdg120+1)
-- Dumped by pg_dump version 16.9 (Debian 16.9-1.pgdg120+1)

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
-- Name: anno; Type: SCHEMA; Schema: -; Owner: genouser
--

CREATE SCHEMA anno;


ALTER SCHEMA anno OWNER TO genouser;

--
-- Name: hdb_catalog; Type: SCHEMA; Schema: -; Owner: genouser
--

CREATE SCHEMA hdb_catalog;


ALTER SCHEMA hdb_catalog OWNER TO genouser;

--
-- Name: legacy; Type: SCHEMA; Schema: -; Owner: genouser
--

CREATE SCHEMA legacy;


ALTER SCHEMA legacy OWNER TO genouser;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: gen_hasura_uuid(); Type: FUNCTION; Schema: hdb_catalog; Owner: genouser
--

CREATE FUNCTION hdb_catalog.gen_hasura_uuid() RETURNS uuid
    LANGUAGE sql
    AS $$select gen_random_uuid()$$;


ALTER FUNCTION hdb_catalog.gen_hasura_uuid() OWNER TO genouser;

--
-- Name: _rp_upsert(text, text, text, text, text, integer, text, text); Type: FUNCTION; Schema: public; Owner: genouser
--

CREATE FUNCTION public._rp_upsert(_rsid text, _gene text, _cond text, _zyg text, _allele text, _w integer, _sum text, _nut text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO risk_panel(rsid,gene,condition,zygosity,risk_allele,weight,summary,nutrition)
  VALUES(_rsid,_gene,_cond,_zyg,_allele,_w,_sum,_nut)
  ON CONFLICT (rsid, zygosity, risk_allele) DO UPDATE
  SET gene=EXCLUDED.gene,
      condition=EXCLUDED.condition,
      weight=EXCLUDED.weight,
      summary=EXCLUDED.summary,
      nutrition=EXCLUDED.nutrition;
END;
$$;


ALTER FUNCTION public._rp_upsert(_rsid text, _gene text, _cond text, _zyg text, _allele text, _w integer, _sum text, _nut text) OWNER TO genouser;

--
-- Name: mark_dup_upload(); Type: FUNCTION; Schema: public; Owner: genouser
--

CREATE FUNCTION public.mark_dup_upload() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare keep_id bigint;
begin
  select id into keep_id
    from uploads
   where sha256 = NEW.sha256
     and coalesce(user_email,'') = coalesce(NEW.user_email,'')
     and id <> NEW.id
   order by id asc
   limit 1;

  if keep_id is not null then
    update uploads
       set status='duplicate',
           notes = coalesce(notes,'') || format(' duplicate_of=%s;', keep_id)
     where id = NEW.id;
  end if;
  return NEW;
end;
$$;


ALTER FUNCTION public.mark_dup_upload() OWNER TO genouser;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: stg_vep_json; Type: TABLE; Schema: anno; Owner: genouser
--

CREATE TABLE anno.stg_vep_json (
    raw jsonb
);


ALTER TABLE anno.stg_vep_json OWNER TO genouser;

--
-- Name: vep_transcript_effects; Type: TABLE; Schema: anno; Owner: genouser
--

CREATE TABLE anno.vep_transcript_effects (
    effect_id bigint NOT NULL,
    variant_id bigint NOT NULL,
    gene_id text,
    gene_symbol text,
    transcript_id text,
    biotype text,
    is_canonical boolean,
    consequence_terms text[] NOT NULL,
    impact text,
    hgvsc text,
    hgvsp text,
    protein_id text,
    amino_acids text,
    codons text,
    exon text,
    intron text,
    sift_score numeric,
    sift_prediction text,
    polyphen_score numeric,
    polyphen_prediction text,
    af_gnomad numeric,
    clin_sig text[],
    extra jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE anno.vep_transcript_effects OWNER TO genouser;

--
-- Name: vep_transcript_effects_effect_id_seq; Type: SEQUENCE; Schema: anno; Owner: genouser
--

CREATE SEQUENCE anno.vep_transcript_effects_effect_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE anno.vep_transcript_effects_effect_id_seq OWNER TO genouser;

--
-- Name: vep_transcript_effects_effect_id_seq; Type: SEQUENCE OWNED BY; Schema: anno; Owner: genouser
--

ALTER SEQUENCE anno.vep_transcript_effects_effect_id_seq OWNED BY anno.vep_transcript_effects.effect_id;


--
-- Name: hdb_action_log; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_action_log (
    id uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    action_name text,
    input_payload jsonb NOT NULL,
    request_headers jsonb NOT NULL,
    session_variables jsonb NOT NULL,
    response_payload jsonb,
    errors jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    response_received_at timestamp with time zone,
    status text NOT NULL,
    CONSTRAINT hdb_action_log_status_check CHECK ((status = ANY (ARRAY['created'::text, 'processing'::text, 'completed'::text, 'error'::text])))
);


ALTER TABLE hdb_catalog.hdb_action_log OWNER TO genouser;

--
-- Name: hdb_cron_event_invocation_logs; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_cron_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE hdb_catalog.hdb_cron_event_invocation_logs OWNER TO genouser;

--
-- Name: hdb_cron_events; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_cron_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    trigger_name text NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);


ALTER TABLE hdb_catalog.hdb_cron_events OWNER TO genouser;

--
-- Name: hdb_metadata; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_metadata (
    id integer NOT NULL,
    metadata json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL
);


ALTER TABLE hdb_catalog.hdb_metadata OWNER TO genouser;

--
-- Name: hdb_scheduled_event_invocation_logs; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_scheduled_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE hdb_catalog.hdb_scheduled_event_invocation_logs OWNER TO genouser;

--
-- Name: hdb_scheduled_events; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_scheduled_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    webhook_conf json NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    retry_conf json,
    payload json,
    header_conf json,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    comment text,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);


ALTER TABLE hdb_catalog.hdb_scheduled_events OWNER TO genouser;

--
-- Name: hdb_schema_notifications; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_schema_notifications (
    id integer NOT NULL,
    notification json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL,
    instance_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT hdb_schema_notifications_id_check CHECK ((id = 1))
);


ALTER TABLE hdb_catalog.hdb_schema_notifications OWNER TO genouser;

--
-- Name: hdb_version; Type: TABLE; Schema: hdb_catalog; Owner: genouser
--

CREATE TABLE hdb_catalog.hdb_version (
    hasura_uuid uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    version text NOT NULL,
    upgraded_on timestamp with time zone NOT NULL,
    cli_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    console_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    ee_client_id text,
    ee_client_secret text
);


ALTER TABLE hdb_catalog.hdb_version OWNER TO genouser;

--
-- Name: rsids_all; Type: TABLE; Schema: legacy; Owner: genouser
--

CREATE TABLE legacy.rsids_all (
    rsid text NOT NULL
);


ALTER TABLE legacy.rsids_all OWNER TO genouser;

--
-- Name: rsids_processed; Type: TABLE; Schema: legacy; Owner: genouser
--

CREATE TABLE legacy.rsids_processed (
    rsid text NOT NULL
);


ALTER TABLE legacy.rsids_processed OWNER TO genouser;

--
-- Name: rsids_missing_in_processed; Type: VIEW; Schema: legacy; Owner: genouser
--

CREATE VIEW legacy.rsids_missing_in_processed AS
 SELECT a.rsid
   FROM (legacy.rsids_all a
     LEFT JOIN legacy.rsids_processed p USING (rsid))
  WHERE (p.rsid IS NULL);


ALTER VIEW legacy.rsids_missing_in_processed OWNER TO genouser;

--
-- Name: rsids_present; Type: TABLE; Schema: legacy; Owner: genouser
--

CREATE TABLE legacy.rsids_present (
    rsid text NOT NULL
);


ALTER TABLE legacy.rsids_present OWNER TO genouser;

--
-- Name: rsids_unscored; Type: TABLE; Schema: legacy; Owner: genouser
--

CREATE TABLE legacy.rsids_unscored (
    rsid text NOT NULL
);


ALTER TABLE legacy.rsids_unscored OWNER TO genouser;

--
-- Name: rsids_scored; Type: VIEW; Schema: legacy; Owner: genouser
--

CREATE VIEW legacy.rsids_scored AS
 SELECT a.rsid
   FROM (legacy.rsids_all a
     LEFT JOIN legacy.rsids_unscored u USING (rsid))
  WHERE (u.rsid IS NULL);


ALTER VIEW legacy.rsids_scored OWNER TO genouser;

--
-- Name: summary; Type: VIEW; Schema: legacy; Owner: genouser
--

CREATE VIEW legacy.summary AS
 WITH counts AS (
         SELECT 'all'::text AS k,
            count(*) AS v
           FROM legacy.rsids_all
        UNION ALL
         SELECT 'unscored'::text,
            count(*) AS count
           FROM legacy.rsids_unscored
        UNION ALL
         SELECT 'processed'::text,
            count(*) AS count
           FROM legacy.rsids_processed
        UNION ALL
         SELECT 'present'::text,
            count(*) AS count
           FROM legacy.rsids_present
        ), diffs AS (
         SELECT 'scored'::text AS "?column?",
            count(*) AS count
           FROM legacy.rsids_scored
        UNION ALL
         SELECT 'missing_in_processed'::text,
            count(*) AS count
           FROM legacy.rsids_missing_in_processed
        )
 SELECT counts.k,
    counts.v
   FROM counts
UNION ALL
 SELECT diffs."?column?" AS k,
    diffs.count AS v
   FROM diffs
  ORDER BY 1;


ALTER VIEW legacy.summary OWNER TO genouser;

--
-- Name: genotypes; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.genotypes (
    sample_id integer NOT NULL,
    variant_id bigint NOT NULL,
    gt text,
    gq integer,
    dp integer,
    ad integer[],
    fmt jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.genotypes OWNER TO genouser;

--
-- Name: risk_panel; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.risk_panel (
    rsid text NOT NULL,
    gene text NOT NULL,
    condition text,
    zygosity text NOT NULL,
    risk_allele text NOT NULL,
    weight integer DEFAULT 1 NOT NULL,
    summary text,
    nutrition text,
    CONSTRAINT risk_panel_risk_allele_check CHECK ((risk_allele ~ '^[ACGT]$'::text)),
    CONSTRAINT risk_panel_zygosity_check CHECK ((zygosity = ANY (ARRAY['any'::text, 'het'::text, 'hom'::text])))
);


ALTER TABLE public.risk_panel OWNER TO genouser;

--
-- Name: samples; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.samples (
    sample_id integer NOT NULL,
    external_id text,
    sex text,
    ancestry text,
    notes text,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT samples_sex_check CHECK (((sex = ANY (ARRAY['male'::text, 'female'::text])) OR (sex IS NULL)))
);


ALTER TABLE public.samples OWNER TO genouser;

--
-- Name: samples_sample_id_seq; Type: SEQUENCE; Schema: public; Owner: genouser
--

CREATE SEQUENCE public.samples_sample_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.samples_sample_id_seq OWNER TO genouser;

--
-- Name: samples_sample_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: genouser
--

ALTER SEQUENCE public.samples_sample_id_seq OWNED BY public.samples.sample_id;


--
-- Name: staging_array_calls; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.staging_array_calls (
    id bigint NOT NULL,
    upload_id bigint,
    sample_label text,
    rsid text,
    chrom text,
    pos integer,
    allele1 text,
    allele2 text,
    genotype text,
    raw_line text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.staging_array_calls OWNER TO genouser;

--
-- Name: staging_array_calls_id_seq; Type: SEQUENCE; Schema: public; Owner: genouser
--

CREATE SEQUENCE public.staging_array_calls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staging_array_calls_id_seq OWNER TO genouser;

--
-- Name: staging_array_calls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: genouser
--

ALTER SEQUENCE public.staging_array_calls_id_seq OWNED BY public.staging_array_calls.id;


--
-- Name: uploads; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.uploads (
    id bigint NOT NULL,
    received_at timestamp with time zone DEFAULT now(),
    sample_label text,
    original_name text,
    stored_path text,
    size_bytes bigint,
    sha256 text,
    kind text,
    status text DEFAULT 'received'::text,
    notes text,
    claim_code text,
    user_email text,
    email_norm text GENERATED ALWAYS AS (COALESCE(user_email, ''::text)) STORED
);


ALTER TABLE public.uploads OWNER TO genouser;

--
-- Name: uploads_id_seq; Type: SEQUENCE; Schema: public; Owner: genouser
--

CREATE SEQUENCE public.uploads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.uploads_id_seq OWNER TO genouser;

--
-- Name: uploads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: genouser
--

ALTER SEQUENCE public.uploads_id_seq OWNED BY public.uploads.id;


--
-- Name: variants; Type: TABLE; Schema: public; Owner: genouser
--

CREATE TABLE public.variants (
    variant_id bigint NOT NULL,
    chrom text NOT NULL,
    pos integer NOT NULL,
    ref text NOT NULL,
    alt text NOT NULL,
    rsid text,
    gene text,
    impact text,
    info jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.variants OWNER TO genouser;

--
-- Name: variants_variant_id_seq; Type: SEQUENCE; Schema: public; Owner: genouser
--

CREATE SEQUENCE public.variants_variant_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.variants_variant_id_seq OWNER TO genouser;

--
-- Name: variants_variant_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: genouser
--

ALTER SEQUENCE public.variants_variant_id_seq OWNED BY public.variants.variant_id;


--
-- Name: vep_transcript_effects effect_id; Type: DEFAULT; Schema: anno; Owner: genouser
--

ALTER TABLE ONLY anno.vep_transcript_effects ALTER COLUMN effect_id SET DEFAULT nextval('anno.vep_transcript_effects_effect_id_seq'::regclass);


--
-- Name: samples sample_id; Type: DEFAULT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.samples ALTER COLUMN sample_id SET DEFAULT nextval('public.samples_sample_id_seq'::regclass);


--
-- Name: staging_array_calls id; Type: DEFAULT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.staging_array_calls ALTER COLUMN id SET DEFAULT nextval('public.staging_array_calls_id_seq'::regclass);


--
-- Name: uploads id; Type: DEFAULT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.uploads ALTER COLUMN id SET DEFAULT nextval('public.uploads_id_seq'::regclass);


--
-- Name: variants variant_id; Type: DEFAULT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.variants ALTER COLUMN variant_id SET DEFAULT nextval('public.variants_variant_id_seq'::regclass);


--
-- Name: vep_transcript_effects vep_transcript_effects_pkey; Type: CONSTRAINT; Schema: anno; Owner: genouser
--

ALTER TABLE ONLY anno.vep_transcript_effects
    ADD CONSTRAINT vep_transcript_effects_pkey PRIMARY KEY (effect_id);


--
-- Name: hdb_action_log hdb_action_log_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_action_log
    ADD CONSTRAINT hdb_action_log_pkey PRIMARY KEY (id);


--
-- Name: hdb_cron_event_invocation_logs hdb_cron_event_invocation_logs_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
    ADD CONSTRAINT hdb_cron_event_invocation_logs_pkey PRIMARY KEY (id);


--
-- Name: hdb_cron_events hdb_cron_events_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_events
    ADD CONSTRAINT hdb_cron_events_pkey PRIMARY KEY (id);


--
-- Name: hdb_metadata hdb_metadata_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_metadata
    ADD CONSTRAINT hdb_metadata_pkey PRIMARY KEY (id);


--
-- Name: hdb_metadata hdb_metadata_resource_version_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_metadata
    ADD CONSTRAINT hdb_metadata_resource_version_key UNIQUE (resource_version);


--
-- Name: hdb_scheduled_event_invocation_logs hdb_scheduled_event_invocation_logs_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
    ADD CONSTRAINT hdb_scheduled_event_invocation_logs_pkey PRIMARY KEY (id);


--
-- Name: hdb_scheduled_events hdb_scheduled_events_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_events
    ADD CONSTRAINT hdb_scheduled_events_pkey PRIMARY KEY (id);


--
-- Name: hdb_schema_notifications hdb_schema_notifications_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_schema_notifications
    ADD CONSTRAINT hdb_schema_notifications_pkey PRIMARY KEY (id);


--
-- Name: hdb_version hdb_version_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_version
    ADD CONSTRAINT hdb_version_pkey PRIMARY KEY (hasura_uuid);


--
-- Name: rsids_all rsids_all_pkey; Type: CONSTRAINT; Schema: legacy; Owner: genouser
--

ALTER TABLE ONLY legacy.rsids_all
    ADD CONSTRAINT rsids_all_pkey PRIMARY KEY (rsid);


--
-- Name: rsids_present rsids_present_pkey; Type: CONSTRAINT; Schema: legacy; Owner: genouser
--

ALTER TABLE ONLY legacy.rsids_present
    ADD CONSTRAINT rsids_present_pkey PRIMARY KEY (rsid);


--
-- Name: rsids_processed rsids_processed_pkey; Type: CONSTRAINT; Schema: legacy; Owner: genouser
--

ALTER TABLE ONLY legacy.rsids_processed
    ADD CONSTRAINT rsids_processed_pkey PRIMARY KEY (rsid);


--
-- Name: rsids_unscored rsids_unscored_pkey; Type: CONSTRAINT; Schema: legacy; Owner: genouser
--

ALTER TABLE ONLY legacy.rsids_unscored
    ADD CONSTRAINT rsids_unscored_pkey PRIMARY KEY (rsid);


--
-- Name: genotypes genotypes_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.genotypes
    ADD CONSTRAINT genotypes_pkey PRIMARY KEY (sample_id, variant_id);


--
-- Name: risk_panel risk_panel_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.risk_panel
    ADD CONSTRAINT risk_panel_pkey PRIMARY KEY (rsid, zygosity, risk_allele);


--
-- Name: samples samples_external_id_key; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.samples
    ADD CONSTRAINT samples_external_id_key UNIQUE (external_id);


--
-- Name: samples samples_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.samples
    ADD CONSTRAINT samples_pkey PRIMARY KEY (sample_id);


--
-- Name: staging_array_calls staging_array_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.staging_array_calls
    ADD CONSTRAINT staging_array_calls_pkey PRIMARY KEY (id);


--
-- Name: uploads uploads_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.uploads
    ADD CONSTRAINT uploads_pkey PRIMARY KEY (id);


--
-- Name: variants uq_variant; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT uq_variant UNIQUE (chrom, pos, ref, alt);


--
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (variant_id);


--
-- Name: vep_eff_cons_gin; Type: INDEX; Schema: anno; Owner: genouser
--

CREATE INDEX vep_eff_cons_gin ON anno.vep_transcript_effects USING gin (consequence_terms);


--
-- Name: vep_eff_gene_idx; Type: INDEX; Schema: anno; Owner: genouser
--

CREATE INDEX vep_eff_gene_idx ON anno.vep_transcript_effects USING btree (gene_symbol);


--
-- Name: vep_eff_variant_idx; Type: INDEX; Schema: anno; Owner: genouser
--

CREATE INDEX vep_eff_variant_idx ON anno.vep_transcript_effects USING btree (variant_id);


--
-- Name: hdb_cron_event_invocation_event_id; Type: INDEX; Schema: hdb_catalog; Owner: genouser
--

CREATE INDEX hdb_cron_event_invocation_event_id ON hdb_catalog.hdb_cron_event_invocation_logs USING btree (event_id);


--
-- Name: hdb_cron_event_status; Type: INDEX; Schema: hdb_catalog; Owner: genouser
--

CREATE INDEX hdb_cron_event_status ON hdb_catalog.hdb_cron_events USING btree (status);


--
-- Name: hdb_cron_events_unique_scheduled; Type: INDEX; Schema: hdb_catalog; Owner: genouser
--

CREATE UNIQUE INDEX hdb_cron_events_unique_scheduled ON hdb_catalog.hdb_cron_events USING btree (trigger_name, scheduled_time) WHERE (status = 'scheduled'::text);


--
-- Name: hdb_scheduled_event_status; Type: INDEX; Schema: hdb_catalog; Owner: genouser
--

CREATE INDEX hdb_scheduled_event_status ON hdb_catalog.hdb_scheduled_events USING btree (status);


--
-- Name: hdb_version_one_row; Type: INDEX; Schema: hdb_catalog; Owner: genouser
--

CREATE UNIQUE INDEX hdb_version_one_row ON hdb_catalog.hdb_version USING btree (((version IS NOT NULL)));


--
-- Name: genotypes_pair_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX genotypes_pair_idx ON public.genotypes USING btree (sample_id, variant_id);


--
-- Name: genotypes_samp_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX genotypes_samp_idx ON public.genotypes USING btree (sample_id);


--
-- Name: genotypes_var_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX genotypes_var_idx ON public.genotypes USING btree (variant_id);


--
-- Name: idx_genotypes_sample; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX idx_genotypes_sample ON public.genotypes USING btree (sample_id);


--
-- Name: idx_genotypes_variant; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX idx_genotypes_variant ON public.genotypes USING btree (variant_id);


--
-- Name: idx_variants_chrpos; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX idx_variants_chrpos ON public.variants USING btree (chrom, pos);


--
-- Name: idx_variants_gene; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX idx_variants_gene ON public.variants USING btree (gene);


--
-- Name: staging_array_calls_rsid; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX staging_array_calls_rsid ON public.staging_array_calls USING btree (rsid);


--
-- Name: staging_array_calls_upload_id; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX staging_array_calls_upload_id ON public.staging_array_calls USING btree (upload_id);


--
-- Name: uploads_claim_code_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX uploads_claim_code_idx ON public.uploads USING btree (claim_code);


--
-- Name: uploads_received_at_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX uploads_received_at_idx ON public.uploads USING btree (received_at);


--
-- Name: uploads_unique_emailsha; Type: INDEX; Schema: public; Owner: genouser
--

CREATE UNIQUE INDEX uploads_unique_emailsha ON public.uploads USING btree (email_norm, sha256) WHERE (status <> ALL (ARRAY['duplicate'::text, 'deleted'::text]));


--
-- Name: uploads_user_email_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX uploads_user_email_idx ON public.uploads USING btree (user_email);


--
-- Name: variants_chrom_pos_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX variants_chrom_pos_idx ON public.variants USING btree (chrom, pos);


--
-- Name: variants_rsid_idx; Type: INDEX; Schema: public; Owner: genouser
--

CREATE INDEX variants_rsid_idx ON public.variants USING btree (rsid);


--
-- Name: uploads trg_mark_dup_upload; Type: TRIGGER; Schema: public; Owner: genouser
--

CREATE TRIGGER trg_mark_dup_upload AFTER INSERT ON public.uploads FOR EACH ROW EXECUTE FUNCTION public.mark_dup_upload();


--
-- Name: vep_transcript_effects vep_transcript_effects_variant_id_fkey; Type: FK CONSTRAINT; Schema: anno; Owner: genouser
--

ALTER TABLE ONLY anno.vep_transcript_effects
    ADD CONSTRAINT vep_transcript_effects_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(variant_id) ON DELETE CASCADE;


--
-- Name: hdb_cron_event_invocation_logs hdb_cron_event_invocation_logs_event_id_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
    ADD CONSTRAINT hdb_cron_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_cron_events(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: hdb_scheduled_event_invocation_logs hdb_scheduled_event_invocation_logs_event_id_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: genouser
--

ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
    ADD CONSTRAINT hdb_scheduled_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_scheduled_events(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: genotypes genotypes_sample_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.genotypes
    ADD CONSTRAINT genotypes_sample_id_fkey FOREIGN KEY (sample_id) REFERENCES public.samples(sample_id) ON DELETE CASCADE;


--
-- Name: genotypes genotypes_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.genotypes
    ADD CONSTRAINT genotypes_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(variant_id) ON DELETE CASCADE;


--
-- Name: staging_array_calls staging_array_calls_upload_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: genouser
--

ALTER TABLE ONLY public.staging_array_calls
    ADD CONSTRAINT staging_array_calls_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES public.uploads(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

