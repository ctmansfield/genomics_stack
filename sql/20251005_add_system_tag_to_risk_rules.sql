BEGIN;

-- Add system_tag column to risk_rules if missing; default 'General'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='risk_rules' AND column_name='system_tag'
  ) THEN
    EXECUTE 'ALTER TABLE public.risk_rules ADD COLUMN system_tag text NOT NULL DEFAULT ''General''';
  END IF;
END$$;

-- Optional: index to filter by system quickly
CREATE INDEX IF NOT EXISTS idx_risk_rules_system ON public.risk_rules(system_tag);

COMMIT;
