-- Normalize a genotype string into 'het' | 'hom' | 'ref' (or NULL)
CREATE OR REPLACE FUNCTION public.infer_zygosity(gt text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s  text := lower(coalesce(gt,''));
  a1 text;
  a2 text;
BEGIN
  IF s = '' THEN RETURN NULL; END IF;
  IF s IN ('het','hom','ref') THEN RETURN s; END IF;

  -- 0/0, 0/1, 1/1 or with pipes
  IF s ~ '^[01][/|][01]$' THEN
    IF substring(s,1,1) = substring(s,3,1) THEN
      IF substring(s,1,1) = '1' THEN RETURN 'hom'; ELSE RETURN 'ref'; END IF;
    ELSE
      RETURN 'het';
    END IF;
  END IF;

  -- A/G or a|g
  IF s ~ '^[acgt][/|][acgt]$' THEN
    a1 := substring(s,1,1);
    a2 := substring(s,3,1);
    IF a1 = a2 THEN RETURN 'hom'; ELSE RETURN 'het'; END IF;
  END IF;

  -- AG, AA (two letters, no separator)
  IF s ~ '^[acgt]{2}$' THEN
    a1 := substring(s,1,1);
    a2 := substring(s,2,1);
    IF a1 = a2 THEN RETURN 'hom'; ELSE RETURN 'het'; END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- Recompute risk_hits for a given upload from whichever source exists
CREATE OR REPLACE FUNCTION public.risk_hits_recalc(p_upload_id bigint)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  rows int := 0;
BEGIN
  DELETE FROM public.risk_hits WHERE upload_id = p_upload_id;

  -- Path A: genotypes(upload_id, variant_id, one of: zygosity|gt|genotype|call)
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='genotypes') AND
     EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='genotypes' AND column_name='upload_id') AND
     EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='genotypes' AND column_name='variant_id')
  THEN
    INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
    SELECT p_upload_id,
           r.rule_id,
           z AS zygosity,
           CASE z WHEN 'hom' THEN r.weight*2.0
                  WHEN 'het' THEN r.weight*1.0
                  ELSE 0::numeric END AS score
    FROM public.risk_rules r
    JOIN (
      SELECT g.variant_id,
             public.infer_zygosity(
               COALESCE(
                 (SELECT g.zygosity  WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='zygosity')),
                 (SELECT g.gt        WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='gt')),
                 (SELECT g.genotype  WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='genotype')),
                 (SELECT g.call      WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='genotypes' AND column_name='call'))
               )
             ) AS z
      FROM public.genotypes g
      WHERE g.upload_id = p_upload_id
    ) g ON g.variant_id = r.variant_id
    WHERE r.is_active AND g.z IN ('het','hom');

    GET DIAGNOSTICS rows = ROW_COUNT;
    IF rows > 0 THEN RETURN rows; END IF;
  END IF;

  -- Path B: staging_array_calls(upload_id, rsid|locus, zygosity|genotype|call)
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='staging_array_calls') THEN

    -- Prefer RSID join if present
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='rsid') THEN
      INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
      SELECT p_upload_id, r.rule_id, z AS zygosity,
             CASE z WHEN 'hom' THEN r.weight*2.0
                    WHEN 'het' THEN r.weight*1.0
                    ELSE 0::numeric END
      FROM public.risk_rules r
      JOIN public.variants v ON v.variant_id = r.variant_id
      JOIN (
        SELECT s.rsid,
               public.infer_zygosity(
                 COALESCE(
                   (SELECT s.zygosity WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='zygosity')),
                   (SELECT s.genotype WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='genotype')),
                   (SELECT s.call     WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='call'))
                 )
               ) AS z
        FROM public.staging_array_calls s
        WHERE s.upload_id = p_upload_id
      ) s ON s.rsid = v.rsid
      WHERE r.is_active AND s.z IN ('het','hom');

      GET DIAGNOSTICS rows = ROW_COUNT;
      IF rows > 0 THEN RETURN rows; END IF;
    END IF;

    -- Fallback: locus join
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='chrom') AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='pos')   AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='ref')   AND
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='alt')
    THEN
      INSERT INTO public.risk_hits (upload_id, rule_id, zygosity, score)
      SELECT p_upload_id, r.rule_id, z AS zygosity,
             CASE z WHEN 'hom' THEN r.weight*2.0
                    WHEN 'het' THEN r.weight*1.0
                    ELSE 0::numeric END
      FROM public.risk_rules r
      JOIN public.variants v ON v.variant_id = r.variant_id
      JOIN (
        SELECT s.chrom, s.pos, s.ref, s.alt,
               public.infer_zygosity(
                 COALESCE(
                   (SELECT s.zygosity WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='zygosity')),
                   (SELECT s.genotype WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='genotype')),
                   (SELECT s.call     WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staging_array_calls' AND column_name='call'))
                 )
               ) AS z
        FROM public.staging_array_calls s
        WHERE s.upload_id = p_upload_id
      ) s ON s.chrom=v.chrom AND s.pos=v.pos AND s.ref=v.ref AND s.alt=v.alt
      WHERE r.is_active AND s.z IN ('het','hom');

      GET DIAGNOSTICS rows = ROW_COUNT;
      IF rows > 0 THEN RETURN rows; END IF;
    END IF;
  END IF;

  RETURN rows;
END;
$$;
