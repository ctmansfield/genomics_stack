BEGIN;

-- Enums (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='curated_category') THEN
    CREATE TYPE curated_category AS ENUM
      ('GENERAL','LIPIDS','METHYLATION','DETOX','IMMUNE','NEURO','HORMONE');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='evidence_level') THEN
    CREATE TYPE evidence_level AS ENUM
      ('unspecified','limited','moderate','strong','robust');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='risk_direction') THEN
    CREATE TYPE risk_direction AS ENUM
      ('UNKNOWN','INCREASE','DECREASE','MIXED','NEUTRAL');
  END IF;
END$$;

-- Core table (idempotent; minimal columns needed by loader & reports)
CREATE TABLE IF NOT EXISTS curated_rsid (
  rsid             TEXT PRIMARY KEY,
  category         curated_category NOT NULL DEFAULT 'GENERAL',
  layman_summary   TEXT             NOT NULL,
  medical_relevance TEXT            NULL,
  nutrition_support JSONB           NOT NULL DEFAULT '{}'::jsonb,
  evidence         evidence_level   NOT NULL DEFAULT 'unspecified',
  risk             risk_direction   NOT NULL DEFAULT 'UNKNOWN',
  citations        TEXT             NULL,
  impact_rank      INT              NULL,
  tags             TEXT[]           NULL,
  created_at       TIMESTAMPTZ      NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ      NOT NULL DEFAULT now()
);

-- updated_at trigger
CREATE OR REPLACE FUNCTION trg_touch_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_curated_rsid_updated ON curated_rsid;
CREATE TRIGGER trg_curated_rsid_updated
BEFORE UPDATE ON curated_rsid
FOR EACH ROW EXECUTE FUNCTION trg_touch_updated_at();

-- helpful indexes
CREATE INDEX IF NOT EXISTS idx_curated_rsid_category ON curated_rsid (category);

COMMIT;
