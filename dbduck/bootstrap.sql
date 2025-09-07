CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS report;

CREATE TABLE IF NOT EXISTS core.samples(
  sample_id   TEXT PRIMARY KEY,
  subject_id  TEXT,
  created_at  TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.files(
  sample_id   TEXT,
  path        TEXT,
  md5         TEXT,
  size_bytes  BIGINT,
  created_at  TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.variants(
  sample_id   TEXT,
  chrom       TEXT,
  pos         BIGINT,
  ref         TEXT,
  alt         TEXT
);

CREATE TABLE IF NOT EXISTS core.annotations(
  sample_id   TEXT,
  chrom       TEXT,
  pos         BIGINT,
  ref         TEXT,
  alt         TEXT,
  consequence TEXT,
  gene        TEXT
);

CREATE OR REPLACE VIEW report.subject_overview AS
  SELECT subject_id, COUNT(DISTINCT sample_id) AS n_samples
  FROM core.samples GROUP BY subject_id;

CREATE OR REPLACE VIEW report.variant_risk AS
  SELECT sample_id, chrom, pos, ref, alt, consequence, gene
  FROM core.annotations
  WHERE 1=0; -- placeholder until enrichment arrives
