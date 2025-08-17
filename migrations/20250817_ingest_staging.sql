BEGIN;
CREATE TABLE IF NOT EXISTS staging_array_calls (
  upload_id     BIGINT      NOT NULL,
  sample_label  TEXT        NOT NULL,
  rsid          TEXT        NOT NULL,
  allele1       TEXT        NOT NULL,
  allele2       TEXT        NOT NULL,
  PRIMARY KEY (upload_id, rsid)
);
CREATE INDEX IF NOT EXISTS idx_staging_array_calls_rsid
  ON staging_array_calls (rsid);
COMMIT;
