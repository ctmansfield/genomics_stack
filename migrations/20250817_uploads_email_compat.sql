BEGIN;
-- Add a plain 'email' column for compatibility with older/newer code paths.
ALTER TABLE uploads
  ADD COLUMN IF NOT EXISTS email text;

-- BEFORE INSERT/UPDATE: if email_raw is missing but email is provided, copy it.
CREATE OR REPLACE FUNCTION uploads_email_compat() RETURNS trigger AS $$
BEGIN
  IF NEW.email_raw IS NULL AND NEW.email IS NOT NULL THEN
    NEW.email_raw := NEW.email;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_uploads_email_compat ON uploads;
CREATE TRIGGER trg_uploads_email_compat
  BEFORE INSERT OR UPDATE ON uploads
  FOR EACH ROW EXECUTE FUNCTION uploads_email_compat();
COMMIT;
