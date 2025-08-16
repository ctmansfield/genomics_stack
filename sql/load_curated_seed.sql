\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE _cur_rsid_stage (
  rsid                   text PRIMARY KEY,
  title                  text,
  layman_desc            text,
  medical_relevance      text,
  nutrition_support_json jsonb,
  citations              text
);

\copy _cur_rsid_stage (rsid,title,layman_desc,medical_relevance,nutrition_support_json,citations) FROM '/root/genomics-stack/curation/curated_rsid_seed.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO curated_rsid (rsid, layman_summary, medical_relevance, nutrition_support, citations)
SELECT
  rsid,
  COALESCE(NULLIF(layman_desc,''), 'TODO: summary pending'),
  NULLIF(medical_relevance,''),
  COALESCE(nutrition_support_json, '{}'::jsonb),
  NULLIF(citations,'')
FROM _cur_rsid_stage
ON CONFLICT (rsid) DO UPDATE
SET layman_summary    = EXCLUDED.layman_summary,
    medical_relevance = EXCLUDED.medical_relevance,
    nutrition_support = EXCLUDED.nutrition_support,
    citations         = EXCLUDED.citations,
    updated_at        = now();

COMMIT;
