BEGIN;
DROP TRIGGER IF EXISTS trg_uploads_email_compat ON uploads;
DROP FUNCTION IF EXISTS uploads_email_compat();
COMMIT;
