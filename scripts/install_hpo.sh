#!/usr/bin/env bash
# Install HPO schema + load + MV without modifying PG* env or passwords.

set +e  # honor your no-strict-mode rule

# --- Require env from your venv; do not set defaults
missing=()
[ -z "${PGHOST:-}" ]      && missing+=("PGHOST")
[ -z "${PGPORT:-}" ]      && missing+=("PGPORT")
[ -z "${PGUSER:-}" ]      && missing+=("PGUSER")
[ -z "${PGDATABASE:-}" ]  && missing+=("PGDATABASE")

if [ ${#missing[@]} -gt 0 ]; then
  echo "[ERROR] Missing required env: ${missing[*]}"
  echo "       Activate your venv that exports these, then re-run."
  exit 1
fi

echo "[INFO] Using PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=$PGUSER PGDATABASE=$PGDATABASE"

# --- Connection test (uses conn string; does not mutate env)
psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -v ON_ERROR_STOP=1 -c '\conninfo' >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "[ERROR] Could not connect with current env (host=$PGHOST port=$PGPORT user=$PGUSER db=$PGDATABASE)."
  echo "       Adjust env and retry (example: export PGPORT=55432)."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
SQL_DIR="${REPO_ROOT}/sql/hpo"
STAGING="/tmp/hpo_gene.tsv"

if [ ! -f "$STAGING" ]; then
  echo "[ERROR] Staging file not found: $STAGING"
  echo "        Run: ./scripts/prepare_hpo_stage.sh   (after setting HPO_SOURCE)"
  exit 1
fi

# --- Apply schema
psql -v ON_ERROR_STOP=1 <<'SQL'
SET statement_timeout='15min';
SET work_mem='256MB';
SET temp_buffers='128MB';
SET enable_nestloop=off;
SQL
if [ $? -ne 0 ]; then echo "[ERROR] Session knobs failed"; exit 1; fi

psql -v ON_ERROR_STOP=1 -f "$SQL_DIR/001_hpo_schema.sql"
if [ $? -ne 0 ]; then echo "[ERROR] Applying schema failed"; exit 1; fi

# --- Stage table
psql -v ON_ERROR_STOP=1 -c "DROP TABLE IF EXISTS public.hpo_stage"
psql -v ON_ERROR_STOP=1 -c "
CREATE TABLE public.hpo_stage (
  raw_gene_symbol text,
  hpo_id          text,
  hpo_label       text,
  evidence        text,
  source          text
)"
# --- Load stage with \copy (separate call)
psql -v ON_ERROR_STOP=1 -c "\copy public.hpo_stage FROM '${STAGING}' WITH (FORMAT text, DELIMITER E'\t', NULL '')"
if [ $? -ne 0 ]; then echo "[ERROR] Copy into stage failed"; exit 1; fi

# --- Build alias→canonical TEMP map
psql -v ON_ERROR_STOP=1 <<'SQL'
SET statement_timeout='15min';
SET work_mem='256MB';
SET temp_buffers='128MB';
SET enable_nestloop=off;

CREATE TEMP TABLE _mv_gsc AS
SELECT alias, canonical FROM public.mv_gene_symbol_canonical;
CREATE INDEX ON _mv_gsc(alias);
SQL
if [ $? -ne 0 ]; then echo "[ERROR] Building _mv_gsc failed"; exit 1; fi

# --- Normalize + upserts (DISTINCT ON, then ON CONFLICT)
psql -v ON_ERROR_STOP=1 <<'SQL'
SET statement_timeout='15min';
SET work_mem='256MB';
SET temp_buffers='128MB';
SET enable_nestloop=off;

CREATE TEMP TABLE _terms AS
SELECT DISTINCT
  upper(hpo_id) AS hpo_id,
  hpo_label     AS label
FROM public.hpo_stage
WHERE hpo_id ~ '^HP:\d{7}$';

INSERT INTO public.hpo_terms (hpo_id, label)
SELECT t.hpo_id, t.label
FROM _terms t
ON CONFLICT (hpo_id) DO UPDATE
  SET label = EXCLUDED.label
  WHERE public.hpo_terms.label IS DISTINCT FROM EXCLUDED.label;

CREATE TEMP TABLE _edges AS
WITH base AS (
  SELECT
    COALESCE(m.canonical, s.raw_gene_symbol) AS gene_symbol,
    upper(s.hpo_id)                           AS hpo_id,
    NULLIF(s.evidence,'')                     AS evidence,
    NULLIF(s.source,'')                       AS source
  FROM public.hpo_stage s
  LEFT JOIN _mv_gsc m ON m.alias = s.raw_gene_symbol
  WHERE s.hpo_id ~ '^HP:\d{7}$'
)
SELECT DISTINCT ON (gene_symbol, hpo_id, coalesce(lower(regexp_replace(coalesce(evidence,''), '\s+', ' ', 'g')), ''))
  gene_symbol, hpo_id, evidence, source
FROM base
ORDER BY gene_symbol, hpo_id, coalesce(lower(regexp_replace(coalesce(evidence,''), '\s+', ' ', 'g')), '');

INSERT INTO public.gene_to_hpo (gene_symbol, hpo_id, evidence, source)
SELECT e.gene_symbol, e.hpo_id, e.evidence, e.source
FROM _edges e
ON CONFLICT (gene_symbol, hpo_id, evidence_norm) DO UPDATE
  SET evidence = EXCLUDED.evidence,
      source   = EXCLUDED.source
  WHERE public.gene_to_hpo.evidence IS DISTINCT FROM EXCLUDED.evidence
     OR public.gene_to_hpo.source   IS DISTINCT FROM EXCLUDED.source;
SQL
if [ $? -ne 0 ]; then echo "[ERROR] Upsert into hpo tables failed"; exit 1; fi

# --- MV create/refresh
psql -v ON_ERROR_STOP=1 -f "$SQL_DIR/010_hpo_mv.sql" || { echo "[ERROR] Creating MV failed"; exit 1; }
psql -v ON_ERROR_STOP=1 -c "REFRESH MATERIALIZED VIEW public.mv_hpo_counts" || { echo "[ERROR] Refreshing MV failed"; exit 1; }

echo "[OK] HPO installation complete."
