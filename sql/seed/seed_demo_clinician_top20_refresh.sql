-- Demo seed + recompute for genome_db (Adminer-ready)
-- Safe to re-run; populates upload_id=900001 and computes risk hits.

-- 1) Genes
INSERT INTO public.genes(symbol, name) VALUES
  ('APOE','Apolipoprotein E'),
  ('MTHFR','Methylenetetrahydrofolate reductase'),
  ('HFE','Homeostatic iron regulator')
ON CONFLICT (symbol) DO NOTHING;

-- 2) Variants
CREATE UNIQUE INDEX IF NOT EXISTS uq_variant ON public.variants(chrom,pos,ref,alt);
INSERT INTO public.variants(chrom,pos,ref,alt,rsid)
VALUES
  ('19', 45411941, 'C', 'T', 'rs429358'),
  ('19', 45412079, 'T', 'C', 'rs7412'),
  ('1',  11856378, 'C', 'T', 'rs1801133'),
  ('6',  26093141, 'G', 'A', 'rs1800562')
ON CONFLICT ON CONSTRAINT uq_variant DO NOTHING;

-- Backfill gene links
UPDATE public.variants v SET gene_id = g.gene_id FROM public.genes g
WHERE (v.rsid IN ('rs429358','rs7412') AND g.symbol='APOE')
   OR (v.rsid = 'rs1801133' AND g.symbol='MTHFR')
   OR (v.rsid = 'rs1800562' AND g.symbol='HFE');

-- 3) Risk rules with system_tag
WITH v AS (
  SELECT rsid, variant_id FROM public.variants WHERE rsid IN ('rs429358','rs7412','rs1801133','rs1800562')
), g AS (
  SELECT symbol, gene_id FROM public.genes WHERE symbol IN ('APOE','MTHFR','HFE')
)
INSERT INTO public.risk_rules(gene_id, variant_id, zygosity_required, weight, short_title,
                              impact_blurb, nutrition_note, evidence_notes, is_active, system_tag)
SELECT * FROM (
  VALUES
  ((SELECT gene_id FROM g WHERE symbol='APOE'),
   (SELECT variant_id FROM v WHERE rsid='rs429358'),
   'any', 1.2,
   'APOE ε4-associated lipid metabolism',
   'ε4 is linked to altered lipid transport and receptor binding; may elevate LDL-C and CVD risk.',
   'Prioritize Mediterranean-style diet; monitor LDL-C; consider DHA/EPA balance.',
   'Moderate to strong evidence across lipid cohorts.', true, 'Cardiovascular'),
  ((SELECT gene_id FROM g WHERE symbol='MTHFR'),
   (SELECT variant_id FROM v WHERE rsid='rs1801133'),
   'any', 1.0,
   'MTHFR C677T reduced enzyme activity',
   'Thermolabile MTHFR reduces 5-MTHF production; can elevate homocysteine.',
   'Ensure adequate folate (5-MTHF), B12, B6; consider homocysteine monitoring.',
   'Strong biochemical evidence; clinical outcomes vary by context.', true, 'Nutrient Metabolism'),
  ((SELECT gene_id FROM g WHERE symbol='HFE'),
   (SELECT variant_id FROM v WHERE rsid='rs1800562'),
   'any', 0.8,
   'HFE C282Y iron uptake increase',
   'Impaired HFE interaction with transferrin receptor can increase intestinal iron absorption.',
   'Monitor ferritin and transferrin saturation; avoid excessive iron/vitamin C if elevated.',
   'Well-established for hemochromatosis in homozygotes; heterozygotes milder.', true, 'Detox/Liver')
) AS t(gene_id, variant_id, zreq, weight, title, blurb, note, ev, active, sys)
ON CONFLICT ON CONSTRAINT uq_risk_rules_def DO NOTHING;

-- 4) Ensure staging table exists
CREATE TABLE IF NOT EXISTS public.staging_array_calls (
  upload_id bigint NOT NULL,
  chrom text,
  pos bigint,
  allele1 text,
  allele2 text,
  rsid text,
  genotype text,
  zygosity text,
  call text
);

-- 5) Seed genotypes for upload 900001
DELETE FROM public.staging_array_calls WHERE upload_id = 900001;
INSERT INTO public.staging_array_calls(upload_id, rsid, genotype) VALUES
  (900001, 'rs429358', '0/1'),
  (900001, 'rs1801133', '1/1'),
  (900001, 'rs1800562', '0/1');

-- 6) Recompute risk hits
SELECT public.risk_hits_recalc(900001);

-- 7) Diagnostics
SELECT 'risk_rules' AS name, COUNT(*) AS n FROM public.risk_rules
UNION ALL
SELECT 'staging_rows' AS name, COUNT(*) FROM public.staging_array_calls WHERE upload_id=900001
UNION ALL
SELECT 'risk_hits_900001' AS name, COUNT(*) FROM public.risk_hits WHERE upload_id=900001;
