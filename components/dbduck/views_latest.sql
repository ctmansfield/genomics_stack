-- Latest file per sample_id based on created_at.
CREATE OR REPLACE VIEW core.files_current AS
WITH ranked AS (
  SELECT
    f.*,
    ROW_NUMBER() OVER (PARTITION BY sample_id ORDER BY created_at DESC, path DESC) AS rn
  FROM core.files AS f
)
SELECT * EXCLUDE (rn) FROM ranked WHERE rn = 1;

-- Samples are derived from files; keep a “current” view for symmetry.
CREATE OR REPLACE VIEW core.samples_current AS
SELECT DISTINCT sample_id
FROM core.files_current;
