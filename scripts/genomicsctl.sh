#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
: "${HDB:=postgresql://genouser:a257272733aa65612215928f75083ae9621e9e3876b15f5e@localhost:5433/genomics}"
: "${STACK_DIR:=/root/genomics-stack}"
: "${COMPOSE_FILE:=$STACK_DIR/compose.yml}"
: "${WORKER_SERVICE:=ingest_worker}"
: "${WORKER_CONTAINER:=genomics-stack-ingest_worker-1}"
: "${HASURA_DB_URL_HOST:=$HDB}"   # for legacy commands we print

# ---------- Helpers ----------
pause() { read -rp "Press Enter to continue..."; }
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

psqlq() { PGPASSWORD="$(echo "$HDB" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p')" \
  psql "$HDB" -v ON_ERROR_STOP=1 -F $'\t' -Atc "$*"; }

psqlf() { PGPASSWORD="$(echo "$HDB" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p')" \
  psql "$HDB" -v ON_ERROR_STOP=1 -f "$1"; }

# ---------- Actions ----------
show_uploads() {
  psqlq "SELECT id, sample_label, original_name, stored_path, status, received_at
         FROM public.uploads ORDER BY id DESC LIMIT 20;"
}

promote_upload() {
  local UPLOAD_ID
  read -rp "Upload ID: " UPLOAD_ID
  [[ "$UPLOAD_ID" =~ ^[0-9]+$ ]] || die "Upload ID must be a number"

  # Minimal, stable promote: loci insert + rsid backfill + genotypes insert
  cat >/tmp/promote_upload.sql <<'SQL'
\set ON_ERROR_STOP on
BEGIN;

-- Ensure sample
WITH u AS (SELECT sample_label FROM public.uploads WHERE id = :upload_id)
INSERT INTO public.samples (external_id)
SELECT sample_label FROM u
ON CONFLICT (external_id) DO NOTHING;

-- Distinct valid rows for this upload
DROP TABLE IF EXISTS tmp_promote_rows;
CREATE TEMP TABLE tmp_promote_rows AS
SELECT DISTINCT
       NULLIF(chrom,'')   AS chrom,
       pos::bigint        AS pos,
       NULLIF(allele1,'') AS ref,
       NULLIF(allele2,'') AS alt,
       NULLIF(rsid,'')    AS rsid,
       genotype           AS gt
FROM public.staging_array_calls
WHERE upload_id = :upload_id
  AND chrom <> '' AND allele1 <> '' AND allele2 <> '' AND pos IS NOT NULL;

-- Insert loci (idempotent via uq_variant)
INSERT INTO public.variants (chrom,pos,ref,alt)
SELECT chrom,pos,ref,alt
FROM tmp_promote_rows
ON CONFLICT ON CONSTRAINT uq_variant DO NOTHING;

-- Backfill rsid only where NULL
UPDATE public.variants v
SET rsid = r.rsid
FROM tmp_promote_rows r
WHERE v.chrom=r.chrom AND v.pos=r.pos AND v.ref=r.ref AND v.alt=r.alt
  AND r.rsid IS NOT NULL AND r.rsid <> ''
  AND v.rsid IS NULL;

-- Insert genotypes for this sample
WITH u AS (SELECT sample_label FROM public.uploads WHERE id = :upload_id),
s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u))
INSERT INTO public.genotypes (sample_id, variant_id, gt)
SELECT (SELECT sample_id FROM s), v.variant_id, r.gt
FROM tmp_promote_rows r
JOIN public.variants v
  ON v.chrom=r.chrom AND v.pos=r.pos AND v.ref=r.ref AND v.alt=r.alt
WHERE r.gt IS NOT NULL AND r.gt <> ''
  AND NOT EXISTS (
    SELECT 1 FROM public.genotypes g
    WHERE g.sample_id = (SELECT sample_id FROM s) AND g.variant_id = v.variant_id
  );

-- Mark upload status
UPDATE public.uploads
SET status = 'imported',
    notes  = COALESCE(notes,'') || ' | promoted by genomicsctl at ' || now()
WHERE id = :upload_id;

COMMIT;
SQL
  PGPASSWORD="$(echo "$HDB" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p')" \
    psql "$HDB" -v upload_id="$UPLOAD_ID" -f /tmp/promote_upload.sql
}

rsid_backfill_only() {
  local UPLOAD_ID
  read -rp "Upload ID (RSID backfill only): " UPLOAD_ID
  [[ "$UPLOAD_ID" =~ ^[0-9]+$ ]] || die "Upload ID must be a number"

  cat >/tmp/rsid_backfill.sql <<'SQL'
\set ON_ERROR_STOP on
UPDATE public.variants v
SET rsid = r.rsid
FROM (
  SELECT DISTINCT NULLIF(chrom,'') AS chrom,
                  pos::bigint      AS pos,
                  NULLIF(allele1,'') AS ref,
                  NULLIF(allele2,'') AS alt,
                  NULLIF(rsid,'')  AS rsid
  FROM public.staging_array_calls
  WHERE upload_id = :upload_id
    AND chrom <> '' AND allele1 <> '' AND allele2 <> '' AND pos IS NOT NULL
    AND rsid IS NOT NULL AND rsid <> ''
) r
WHERE v.chrom=r.chrom AND v.pos=r.pos AND v.ref=r.ref AND v.alt=r.alt
  AND v.rsid IS NULL;
SQL
  PGPASSWORD="$(echo "$HDB" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p')" \
    psql "$HDB" -v upload_id="$UPLOAD_ID" -f /tmp/rsid_backfill.sql
}

counts_for_upload() {
  local UPLOAD_ID
  read -rp "Upload ID: " UPLOAD_ID
  psqlq "
WITH u AS (SELECT sample_label FROM public.uploads WHERE id = $UPLOAD_ID),
     s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u))
SELECT (SELECT sample_id FROM s) AS sample_id,
       (SELECT COUNT(*) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s))           AS genotypes,
       (SELECT COUNT(DISTINCT variant_id) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s)) AS distinct_variants;"
}

watch_genotypes() {
  local UPLOAD_ID
  read -rp "Upload ID: " UPLOAD_ID
  watch -n 2 "psql '$HDB' -Atc \"WITH u AS (SELECT sample_label FROM public.uploads WHERE id=$UPLOAD_ID), s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u)) SELECT 'genotypes', COUNT(*) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s);\""
}

tail_worker_logs() {
  local FILTER
  read -rp "Optional grep filter (blank for all): " FILTER
  if [[ -n "${FILTER:-}" ]]; then
    docker logs -f "$WORKER_CONTAINER" 2>&1 | grep -i --line-buffered "$FILTER"
  else
    docker logs -f "$WORKER_CONTAINER"
  fi
}

show_worker_env() {
  docker exec -i "$WORKER_CONTAINER" env | egrep -i 'PGHOST|PGPORT|PGDATABASE|PGUSER|PGPASSWORD|DATABASE_URL'
}

install_psql_in_worker() {
  docker exec -it "$WORKER_CONTAINER" bash -lc '
    set -e
    if command -v psql >/dev/null 2>&1; then
      psql --version
    else
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client
      psql --version
    fi
    PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "select 1;"'
}

write_override_and_restart() {
  install -d "$STACK_DIR"
  cat > "$STACK_DIR/docker-compose.override.yml" <<YAML
services:
  ${WORKER_SERVICE}:
    environment:
      PGHOST: db
      PGPORT: "5432"
      PGDATABASE: genomics
      PGUSER: genouser
      PGPASSWORD: a257272733aa65612215928f75083ae9621e9e3876b15f5e
      DATABASE_URL: postgres://genouser:a257272733aa65612215928f75083ae9621e9e3876b15f5e@db:5432/genomics
    depends_on:
      db:
        condition: service_started
YAML
  docker compose -f "$COMPOSE_FILE" -f "$STACK_DIR/docker-compose.override.yml" up -d --force-recreate "$WORKER_SERVICE"
}

pg_stat_activity() {
  psqlq "SELECT pid, state, wait_event_type, wait_event, now()-xact_start AS xact_age, left(query,120) AS query
         FROM pg_stat_activity WHERE datname = current_database() ORDER BY xact_start;"
}

cancel_backend() {
  local PID
  read -rp "PID to cancel: " PID
  psqlq "SELECT pg_cancel_backend($PID);"
}

terminate_backend() {
  local PID
  read -rp "PID to terminate: " PID
  psqlq "SELECT pg_terminate_backend($PID);"
}

git_commit_repo() {
  local MSG
  read -rp "Commit message: " MSG
  git -C "$STACK_DIR" add -A
  git -C "$STACK_DIR" commit -m "$MSG" || true
  echo "Committed locally. You can push via menu 15."
}

# --- NEW: Backup GitHub main & push both remotes ---
git_backup_and_push() {
  need git
  local TS; TS="$(date +%Y%m%d%H%M%S)"

  # Ensure remotes exist
  git -C "$STACK_DIR" remote get-url github >/dev/null 2>&1 || die "Missing 'github' remote"
  git -C "$STACK_DIR" remote get-url origin >/dev/null 2>&1 || die "Missing 'origin' remote"

  echo "[1/4] Fetch from GitHub..."
  git -C "$STACK_DIR" fetch github

  echo "[2/4] Backup GitHub/main -> backup-main-$TS"
  git -C "$STACK_DIR" push github "refs/remotes/github/main:refs/heads/backup-main-$TS"

  echo "[3/4] Push main to both remotes (origin & github)"
  git -C "$STACK_DIR" push origin main
  git -C "$STACK_DIR" push github main

  echo "[4/4] Push tags to both remotes"
  git -C "$STACK_DIR" push origin --tags
  git -C "$STACK_DIR" push github --tags

  echo "Done. Safety branch on GitHub: backup-main-$TS"
}

# ---------- Menu ----------
menu() {
  cat <<'MENU'
1) Show latest uploads                            6) Tail ingest_worker logs (optional filter)    11) Cancel backend PID
2) Promote an upload (ID → variants/genotypes)    7) Show ingest_worker DB env                    12) Terminate backend PID
3) Safe RSID backfill only                        8) Install psql inside ingest_worker            13) Commit repo changes
4) Counts for an upload                           9) Write override and restart ingest_worker     14) Quit
5) Watch genotypes count (every 2s)              10) pg_stat_activity (current DB)
15) Backup GitHub main & push both remotes
MENU
}

main() {
  while true; do
    menu
    read -rp $'\nChoose an action: ' choice
    case "$choice" in
      1) show_uploads; pause;;
      2) promote_upload; pause;;
      3) rsid_backfill_only; pause;;
      4) counts_for_upload; pause;;
      5) watch_genotypes;;
      6) tail_worker_logs;;
      7) show_worker_env; pause;;
      8) install_psql_in_worker; pause;;
      9) write_override_and_restart; pause;;
      10) pg_stat_activity; pause;;
      11) cancel_backend; pause;;
      12) terminate_backend; pause;;
      13) git_commit_repo; pause;;
      14) exit 0;;
      15) git_backup_and_push; pause;;
      *) echo "invalid";;
    esac
  done
}

main "$@"
