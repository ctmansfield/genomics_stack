CREATE TABLE IF NOT EXISTS public.file_ingest_registry (
  file_id       bigserial PRIMARY KEY,
  file_path     text NOT NULL UNIQUE,
  file_sha256   text NOT NULL,
  expected_rows bigint NOT NULL,
  target_table  regclass NOT NULL,
  loaded_rows   bigint,
  loaded_at     timestamptz,
  status        text CHECK (status IN ('staged','verified','failed')) DEFAULT 'staged',
  notes         text
);
