-- Base uploads + blobs + staging schema to support /upload API (Adminer-ready, idempotent)

-- 1) uploads table (metadata)
CREATE TABLE IF NOT EXISTS public.uploads(
  id bigserial PRIMARY KEY,
  original_name text,
  kind text,
  status text DEFAULT 'received',
  user_email text,
  email_norm text GENERATED ALWAYS AS (coalesce(user_email,'')) STORED,
  stored_path text,
  bytes bigint,
  sha256 text,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS uploads_unique_emailsha
  ON public.uploads(email_norm, sha256)
  WHERE status <> 'duplicate';

-- Mark duplicates trigger/function (idempotent)
CREATE OR REPLACE FUNCTION public.mark_dup_upload() RETURNS trigger AS $$
DECLARE
  keep_id bigint;
BEGIN
  SELECT id INTO keep_id FROM uploads
   WHERE sha256 = NEW.sha256
     AND coalesce(user_email,'') = coalesce(NEW.user_email,'')
     AND id <> NEW.id
   ORDER BY id ASC LIMIT 1;
  IF keep_id IS NOT NULL THEN
    UPDATE uploads
       SET status='duplicate',
           notes = coalesce(notes,'') || format(' duplicate_of=%s;', keep_id)
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mark_dup_upload ON public.uploads;
CREATE TRIGGER trg_mark_dup_upload AFTER INSERT ON public.uploads
FOR EACH ROW EXECUTE FUNCTION public.mark_dup_upload();

-- 2) upload_blobs table to store original file content (sha + text)
CREATE TABLE IF NOT EXISTS public.upload_blobs (
  upload_id bigint PRIMARY KEY REFERENCES public.uploads(id) ON DELETE CASCADE,
  sha256 text,
  content text
);

-- 3) staging table for parsed array/genotype calls
CREATE TABLE IF NOT EXISTS public.staging_array_calls (
  id bigserial PRIMARY KEY,
  upload_id bigint REFERENCES public.uploads(id) ON DELETE CASCADE,
  sample_label text,
  rsid text,
  chrom text,
  pos bigint,
  allele1 text,
  allele2 text,
  genotype text,
  zygosity text,
  call text,
  created_at timestamptz DEFAULT now()
);

-- Ensure sample_label exists if table pre-existed
ALTER TABLE public.staging_array_calls
  ADD COLUMN IF NOT EXISTS sample_label text;

CREATE INDEX IF NOT EXISTS idx_staging_upload ON public.staging_array_calls(upload_id);
CREATE INDEX IF NOT EXISTS idx_staging_rsid   ON public.staging_array_calls(rsid);

-- 4) Sequence fixup (optional safety)
SELECT setval(pg_get_serial_sequence('public.staging_array_calls','id'),
              COALESCE((SELECT MAX(id) FROM public.staging_array_calls),0), true);
SELECT setval(pg_get_serial_sequence('public.uploads','id'),
              COALESCE((SELECT MAX(id) FROM public.uploads),0), true);
