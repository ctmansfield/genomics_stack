BEGIN;
DROP VIEW IF EXISTS report_curated;
CREATE VIEW report_curated AS
SELECT
  c.rsid,
  c.category::text        AS category,
  c.impact_rank,
  c.evidence::text        AS evidence_level,
  c.risk::text            AS risk_direction,
  c.layman_summary,
  c.medical_relevance,
  c.nutrition_support,
  c.citations,
  c.tags,
  c.updated_at
FROM curated_rsid c;
COMMIT;
