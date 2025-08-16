CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE TABLE IF NOT EXISTS ingest_registry (
  file_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  filename text, md5 text, byte_size bigint,
  uploaded_at timestamptz, imported_at timestamptz,
  vep_completed_at timestamptz, annotated_at timestamptz,
  report_generated_at timestamptz, status text, error text,
  total_records int, imported_records int, annotated_records int, report_path text
);
CREATE TABLE IF NOT EXISTS ingest_events (
  event_id bigserial PRIMARY KEY,
  file_id uuid REFERENCES ingest_registry(file_id),
  event_type text NOT NULL,
  event_ts timestamptz NOT NULL DEFAULT now(),
  details jsonb
);
CREATE INDEX IF NOT EXISTS ingest_events_file_id_idx ON ingest_events(file_id);
