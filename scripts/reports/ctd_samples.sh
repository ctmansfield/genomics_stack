#!/usr/bin/env bash
# Sample CTD reports (strict + pruned). Writes CSVs to reports/upload_2/.
# Uses your existing PG env vars (PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD).

OUTDIR="reports/upload_2"
mkdir -p "$OUTDIR"

PSQL="psql -v ON_ERROR_STOP=0 -h ${PGHOST:-localhost} -p ${PGPORT:-5432} -U ${PGUSER:-genouser} -d ${PGDATABASE:-genome_db}"

echo "[1/6] Family distribution (STRICT) -> $OUTDIR/ctd_family_distribution_strict.csv"
$PSQL -c "\copy (
  SELECT action_family, COUNT(*) AS n_edges
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
  GROUP BY 1
  ORDER BY n_edges DESC
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_family_distribution_strict.csv"

echo "[2/6] Top genes pruned (counts) -> $OUTDIR/ctd_top_pruned_genes.csv"
$PSQL -c "\copy (
  SELECT gene_symbol, n_pruned
  FROM public.v_ctd_pruned_by_gene
  ORDER BY n_pruned DESC, gene_symbol
  LIMIT 200
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_top_pruned_genes.csv"

echo "[3/6] Top chemicals pruned (with names) -> $OUTDIR/ctd_top_pruned_chemicals.csv"
$PSQL -c "\copy (
  SELECT
    p.chem_id,
    COALESCE(c.name, c.mesh_id) AS chem_name,
    p.n_pruned
  FROM public.v_ctd_pruned_by_chemical p
  LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id
  ORDER BY p.n_pruned DESC, p.chem_id
  LIMIT 200
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_top_pruned_chemicals.csv"

echo "[4/6] Sample pruned edges (with names) -> $OUTDIR/ctd_pruned_edges_sample.csv"
$PSQL -c "\copy (
  SELECT gene_symbol, chem_id, chem_name, action_norm, action_family
  FROM public.v_ctd_edges_pruned_with_names
  ORDER BY gene_symbol, chem_id
  LIMIT 1000
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_pruned_edges_sample.csv"

echo "[5/6] Full vs STRICT by gene (diff) -> $OUTDIR/ctd_full_vs_strict_by_gene.csv"
$PSQL -c "\copy (
WITH cte_full AS (
  SELECT gene_symbol, action_family, COUNT(*) AS n
  FROM public.v_gene_to_chemical_enriched
  GROUP BY 1,2
),
cte_strict AS (
  SELECT gene_symbol, action_family, COUNT(*) AS n
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict
  GROUP BY 1,2
)
SELECT
  COALESCE(f.gene_symbol, s.gene_symbol) AS gene_symbol,
  COALESCE(f.action_family, s.action_family) AS action_family,
  f.n AS n_full,
  s.n AS n_strict,
  COALESCE(f.n,0) - COALESCE(s.n,0) AS pruned
FROM cte_full f
FULL OUTER JOIN cte_strict s
  ON f.gene_symbol = s.gene_symbol AND f.action_family = s.action_family
ORDER BY gene_symbol, action_family
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_full_vs_strict_by_gene.csv"

echo "[6/6] Sentinel genes deep-dive -> $OUTDIR/ctd_strict_detail_sentinels.csv"
$PSQL -c "\copy (
WITH strict AS (
  SELECT gene_symbol, chem_id, action_norm,
         public.ctd_action_family(action_norm) AS action_family
  FROM public.v_ctd_enriched_strict_v2
  WHERE is_strict AND gene_symbol IN ('TP53','APOE','PCSK9')
),
roll AS (
  SELECT gene_symbol, action_family, COUNT(*) AS n_edges
  FROM strict
  GROUP BY 1,2
)
SELECT r.gene_symbol, r.action_family, r.n_edges,
       s.chem_id,
       COALESCE(c.name, c.mesh_id) AS chem_name,
       s.action_norm
FROM roll r
LEFT JOIN strict s ON s.gene_symbol = r.gene_symbol AND s.action_family = r.action_family
LEFT JOIN public.chemicals c ON c.chem_id = s.chem_id
ORDER BY r.gene_symbol, r.action_family, chem_name NULLS LAST
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/ctd_strict_detail_sentinels.csv"

echo "Done. Files in $OUTDIR:"
ls -lh "$OUTDIR"/ctd_*.csv 2>/dev/null || true
