CREATE TABLE IF NOT EXISTS public.annotated_variants (
  chrom               text    NOT NULL,
  pos                 bigint  NOT NULL,
  ref                 text    NOT NULL,
  alt                 text    NOT NULL,
  rsid                text,
  gene_symbol         text,
  gene_id             text,
  transcript_id       text,
  biotype             text,
  consequence         text,
  impact              text,
  hgvsc               text,
  hgvsp               text,
  canonical           boolean,
  exon                text,
  intron              text,
  protein_position    text,
  amino_acids         text,
  codons              text,
  strand              smallint,
  existing_variation  text,
  af_gnomad           double precision,
  af_afr              double precision,
  af_amr              double precision,
  af_eas              double precision,
  af_eur              double precision,
  af_sas              double precision,
  clin_sig            text,
  sift                text,
  polyphen            text,
  cadd_raw            double precision,
  cadd_phred          double precision,
  vep_extra_json      jsonb
);

CREATE TABLE IF NOT EXISTS public.annotated_variants_staging
(LIKE public.annotated_variants INCLUDING ALL);

CREATE OR REPLACE VIEW public.annotated_variants_impact_summary AS
SELECT impact, count(*) AS n
FROM public.annotated_variants
GROUP BY impact
ORDER BY n DESC;
