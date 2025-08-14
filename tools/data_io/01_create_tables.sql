-- 01_create_tables.sql
CREATE SCHEMA IF NOT EXISTS genomics;

CREATE TABLE IF NOT EXISTS genomics.annotated_snps (
    snp_id BIGSERIAL PRIMARY KEY,
    rsid TEXT,
    chrom TEXT NOT NULL,
    pos BIGINT NOT NULL,
    ref TEXT NOT NULL,
    alt TEXT NOT NULL,
    gene TEXT,
    consequence TEXT,
    impact TEXT,
    clin_sig TEXT,
    af DOUBLE PRECISION,
    annotations JSONB,
    source_file TEXT,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_snp UNIQUE (chrom, pos, ref, alt)
);

CREATE TABLE IF NOT EXISTS genomics.annotated_snps_staging (
    rsid TEXT,
    chrom TEXT,
    pos BIGINT,
    ref TEXT,
    alt TEXT,
    gene TEXT,
    consequence TEXT,
    impact TEXT,
    clin_sig TEXT,
    af DOUBLE PRECISION,
    annotations JSONB,
    source_file TEXT
);

CREATE INDEX IF NOT EXISTS idx_snps_rsid ON genomics.annotated_snps (rsid);
CREATE INDEX IF NOT EXISTS idx_snps_gene ON genomics.annotated_snps (gene);
CREATE INDEX IF NOT EXISTS idx_snps_chrom_pos ON genomics.annotated_snps (chrom, pos);
