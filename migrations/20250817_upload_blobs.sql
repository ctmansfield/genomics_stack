BEGIN;
CREATE TABLE IF NOT EXISTS public.upload_blobs (
  upload_id BIGINT PRIMARY KEY REFERENCES public.uploads(id) ON DELETE CASCADE,
  sha256    TEXT    NOT NULL,
  content   TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_upload_blobs_sha ON public.upload_blobs(sha256);
COMMIT;
