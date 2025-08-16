-- Add/modify curated rows here and commit this file.
-- Example entries:
INSERT INTO curated_rsid (rsid, category, layman_summary, medical_relevance, nutrition_support, evidence, risk, impact_rank, citations, tags)
VALUES
('rs123','GENERAL','…','…','{"diet":["…"],"notes":"…"]}'::jsonb,'moderate','MIXED',10,'PMID:12345678',ARRAY['demo'])
ON CONFLICT (rsid) DO UPDATE
SET category=EXCLUDED.category, layman_summary=EXCLUDED.layman_summary,
    medical_relevance=EXCLUDED.medical_relevance, nutrition_support=EXCLUDED.nutrition_support,
    evidence=EXCLUDED.evidence, risk=EXCLUDED.risk, impact_rank=EXCLUDED.impact_rank,
    citations=EXCLUDED.citations, tags=EXCLUDED.tags, updated_at=now();

-- Add more rows below…
