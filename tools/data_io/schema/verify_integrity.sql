-- verify_integrity.sql
SELECT 'row_count', COUNT(*) FROM genomics.annotated_snps
UNION ALL
SELECT 'missing_required_fields', COUNT(*) FROM genomics.annotated_snps
    WHERE chrom IS NULL OR pos IS NULL OR ref IS NULL OR alt IS NULL
UNION ALL
SELECT 'duplicate_key_groups', COUNT(*) FROM (
    SELECT chrom, pos, ref, alt, COUNT(*) c
    FROM genomics.annotated_snps
    GROUP BY 1,2,3,4
    HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'invalid_pos', COUNT(*) FROM genomics.annotated_snps WHERE pos <= 0
UNION ALL
SELECT 'invalid_af', COUNT(*) FROM genomics.annotated_snps WHERE af IS NOT NULL AND (af < 0 OR af > 1);
