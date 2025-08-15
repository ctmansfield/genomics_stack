#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
DB_URL_DEFAULT="postgresql://genouser:${PGPASSWORD:-a257272733aa65612215928f75083ae9621e9e3876b15f5e}@localhost:5433/genomics"
HDB="${HDB:-${HASURA_DB_URL_HOST:-$DB_URL_DEFAULT}}"

STACK_DIR="${STACK_DIR:-/root/genomics-stack}"
WORKER_NAME="${WORKER_NAME:-genomics-stack-ingest_worker-1}"
DB_SERVICE="${DB_SERVICE:-genomics-stack-db-1}"

# ---------- Helpers ----------
_pa() { psql "$HDB" -v ON_ERROR_STOP=1 "$@"; }
prompt() { local p="$1"; read -rp "$p" REPLY || true; echo "${REPLY:-}"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_psql() { command -v psql >/dev/null 2>&1 || die "psql not found on host"; }

# ---------- Actions ----------
latest_uploads() {
  need_psql
  _pa -F $'\t' -Atc "SELECT id, sample_label, original_name, stored_path, status, received_at
                     FROM public.uploads ORDER BY id DESC LIMIT 10;"
}

promote_upload() {
  need_psql
  local upid="${1:-}"; [[ -z "$upid" ]] && upid="$(prompt 'Upload ID: ')"
  [[ -n "$upid" ]] || { echo "no upload id"; return; }
  _pa -v upload_id="$upid" <<'SQL'
\set ON_ERROR_STOP on
BEGIN;

WITH u AS (SELECT sample_label FROM public.uploads WHERE id = :upload_id)
INSERT INTO public.samples (external_id)
SELECT sample_label FROM u
ON CONFLICT (external_id) DO NOTHING;

DROP TABLE IF EXISTS tmp_promote_rows;
CREATE TEMP TABLE tmp_promote_rows AS
SELECT DISTINCT
       NULLIF(chrom,'')        AS chrom,
       pos::bigint             AS pos,
       NULLIF(allele1,'')      AS ref,
       NULLIF(allele2,'')      AS alt,
       NULLIF(rsid,'')         AS rsid,
       genotype                AS gt
FROM public.staging_array_calls
WHERE upload_id = :upload_id
  AND chrom <> '' AND allele1 <> '' AND allele2 <> '' AND pos IS NOT NULL;

INSERT INTO public.variants (chrom,pos,ref,alt)
SELECT chrom,pos,ref,alt
FROM tmp_promote_rows
ON CONFLICT ON CONSTRAINT uq_variant DO NOTHING;

UPDATE public.variants v
SET rsid = r.rsid
FROM (
  SELECT DISTINCT chrom,pos,ref,alt,rsid
  FROM tmp_promote_rows
  WHERE rsid IS NOT NULL AND rsid <> ''
) r
WHERE v.chrom=r.chrom AND v.pos=r.pos AND v.ref=r.ref AND v.alt=r.alt
  AND v.rsid IS NULL;

WITH u AS (SELECT sample_label FROM public.uploads WHERE id = :upload_id),
s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u))
INSERT INTO public.genotypes (sample_id, variant_id, gt)
SELECT (SELECT sample_id FROM s) AS sample_id,
       v.variant_id,
       r.gt
FROM tmp_promote_rows r
JOIN public.variants v
  ON (v.chrom,r.chrom) IS NOT DISTINCT FROM (v.chrom,r.chrom)
 AND  v.pos   = r.pos
 AND (v.ref,r.ref)   IS NOT DISTINCT FROM (v.ref,r.ref)
 AND (v.alt,r.alt)   IS NOT DISTINCT FROM (v.alt,r.alt)
WHERE r.gt IS NOT NULL AND r.gt <> ''
  AND NOT EXISTS (
        SELECT 1 FROM public.genotypes g
        WHERE g.sample_id=(SELECT sample_id FROM s)
          AND g.variant_id=v.variant_id
  );

UPDATE public.uploads
SET status='imported',
    notes = COALESCE(notes,'') || ' | promote@' || now()
WHERE id=:upload_id;

COMMIT;
SQL
  echo "Done."
}

rsid_backfill_only() {
  need_psql
  local upid="${1:-}"; [[ -z "$upid" ]] && upid="$(prompt 'Upload ID (source for RSIDs): ')"
  [[ -n "$upid" ]] || { echo "no upload id"; return; }
  _pa -v upload_id="$upid" <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
DROP TABLE IF EXISTS tmp_promote_rows;
CREATE TEMP TABLE tmp_promote_rows AS
SELECT DISTINCT
       NULLIF(chrom,'')   AS chrom,
       pos::bigint        AS pos,
       NULLIF(allele1,'') AS ref,
       NULLIF(allele2,'') AS alt,
       NULLIF(rsid,'')    AS rsid
FROM public.staging_array_calls
WHERE upload_id = :upload_id
  AND rsid IS NOT NULL AND rsid <> ''
  AND chrom <> '' AND allele1 <> '' AND allele2 <> '' AND pos IS NOT NULL;

UPDATE public.variants v
SET rsid = r.rsid
FROM tmp_promote_rows r
WHERE v.chrom=r.chrom AND v.pos=r.pos AND v.ref=r.ref AND v.alt=r.alt
  AND v.rsid IS NULL;
COMMIT;
SQL
  echo "Backfill complete."
}

counts_for_upload() {
  need_psql
  local upid="${1:-}"; [[ -z "$upid" ]] && upid="$(prompt 'Upload ID: ')"
  [[ -n "$upid" ]] || { echo "no upload id"; return; }
  _pa -Atc "
WITH u AS (SELECT sample_label FROM public.uploads WHERE id = $upid),
     s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u))
SELECT (SELECT sample_id FROM s) AS sample_id,
       (SELECT COUNT(*) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s)) AS genotypes,
       (SELECT COUNT(DISTINCT variant_id) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s)) AS distinct_variants;"
}

watch_genotypes() {
  need_psql
  local upid="${1:-}"; [[ -z "$upid" ]] && upid="$(prompt 'Upload ID: ')"
  [[ -z "$upid" ]] && { echo "no upload id"; return; }
  watch -n 2 "psql \"$HDB\" -Atc \"WITH u AS (SELECT sample_label FROM public.uploads WHERE id=$upid), s AS (SELECT sample_id FROM public.samples WHERE external_id=(SELECT sample_label FROM u)) SELECT 'genotypes', COUNT(*) FROM public.genotypes WHERE sample_id IN (SELECT sample_id FROM s);\""
}

tail_worker_logs() {
  local f="${1:-}"
  if [[ -n "$f" ]]; then
    docker logs -f "$WORKER_NAME" 2>&1 | grep -i --line-buffered "$f"
  else
    docker logs -f "$WORKER_NAME"
  fi
}

show_worker_db_env() {
  docker exec -it "$WORKER_NAME" env | egrep -i 'PGHOST|PGPORT|PGDATABASE|PGUSER|PGPASSWORD|DATABASE_URL'
}

install_psql_in_worker() {
  docker exec -it "$WORKER_NAME" bash -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client && psql --version'
}

override_and_restart_worker() {
  local proto user pass host port db rest
  proto="${HDB%%://*}"
  rest="${HDB#*://}"
  user="${rest%%:*}"; rest="${rest#*:}"
  pass="${rest%%@*}"; rest="${rest#*@}"
  host="${rest%%:*}"; rest="${rest#*:}"
  port="${rest%%/*}"; db="${rest#*/}"

  mkdir -p "$STACK_DIR"
  cat > "$STACK_DIR/docker-compose.override.yml" <<YML
services:
  ingest_worker:
    environment:
      PGHOST: ${host}
      PGPORT: "${port}"
      PGDATABASE: ${db}
      PGUSER: ${user}
      PGPASSWORD: ${pass}
      DATABASE_URL: ${proto}://${user}:${pass}@${host}:${port}/${db}
    depends_on:
      db:
        condition: service_started
YML

  docker compose -f "$STACK_DIR/compose.yml" -f "$STACK_DIR/docker-compose.override.yml" up -d --force-recreate ingest_worker
}

pg_stat_activity_menu() {
  need_psql
  _pa -Atc "SELECT pid, state, wait_event_type, wait_event, now()-xact_start AS xact_age, left(query,120) AS query
            FROM pg_stat_activity WHERE datname = current_database()
            ORDER BY xact_start;"
}

cancel_pid() {
  need_psql
  local pid="${1:-}"; [[ -z "$pid" ]] && pid="$(prompt 'PID to pg_cancel_backend(): ')"
  [[ -z "$pid" ]] && { echo "no pid"; return; }
  _pa -Atc "SELECT pg_cancel_backend($pid);"
}

terminate_pid() {
  need_psql
  local pid="${1:-}"; [[ -z "$pid" ]] && pid="$(prompt 'PID to pg_terminate_backend(): ')"
  [[ -z "$pid" ]] && { echo "no pid"; return; }
  _pa -Atc "SELECT pg_terminate_backend($pid);"
}

git_commit_repo_changes() {
  ( cd "$STACK_DIR"
    git add scripts/genomicsctl.sh docker-compose.override.yml || true
    git commit -m "ops: update genomicsctl (menu + noninteractive CLI: promote/backfill/counts/etc.)" || true
    git push -u origin HEAD || true
  )
}

usage() {
cat <<'HELP'
genomicsctl [command] [args]

Commands:
  latest
  promote         --upload-id N
  backfill        --upload-id N
  counts          --upload-id N
  watch           --upload-id N
  logs            [filter]
  env
  psql-install
  override-restart
  pgstat
  cancel          --pid PID
  terminate       --pid PID
  help

If no command is given, an interactive menu is shown.
HELP
}

# ---------- Menu ----------
main_menu() {
  while true; do
    cat <<'MENU'
1) Show latest uploads                            6) Tail ingest_worker logs (optional filter)    11) Cancel backend PID
2) Promote an upload (ID → variants/genotypes)    7) Show ingest_worker DB env                    12) Terminate backend PID
3) Safe RSID backfill only                        8) Install psql inside ingest_worker            13) Commit repo changes
4) Counts for an upload                           9) Write override and restart ingest_worker     14) Quit
5) Watch genotypes count (every 2s)              10) pg_stat_activity (current DB)
MENU
    read -rp "Choose an action: " choice || true
    case "${choice,,}" in
      1) latest_uploads ;;
      2) promote_upload ;;
      3) rsid_backfill_only ;;
      4) counts_for_upload ;;
      5) watch_genotypes ;;
      6) tail_worker_logs ;;
      7) show_worker_db_env ;;
      8) install_psql_in_worker ;;
      9) override_and_restart_worker ;;
     10) pg_stat_activity_menu ;;
     11) cancel_pid ;;
     12) terminate_pid ;;
     13) git_commit_repo_changes ;;
     14|q|quit|exit) exit 0 ;;
      *) echo "invalid" ;;
    esac
  done
}

# ---------- CLI dispatcher ----------
if [[ $# -gt 0 ]]; then
  cmd="$1"; shift || true
  case "$cmd" in
    latest) latest_uploads ;;
    promote)       [[ "${1:-}" == "--upload-id" ]] && shift; promote_upload "${1:-}";;
    backfill)      [[ "${1:-}" == "--upload-id" ]] && shift; rsid_backfill_only "${1:-}";;
    counts)        [[ "${1:-}" == "--upload-id" ]] && shift; counts_for_upload "${1:-}";;
    watch)         [[ "${1:-}" == "--upload-id" ]] && shift; watch_genotypes "${1:-}";;
    logs)          tail_worker_logs "${1:-}";;
    env)           show_worker_db_env ;;
    psql-install)  install_psql_in_worker ;;
    override-restart) override_and_restart_worker ;;
    pgstat)        pg_stat_activity_menu ;;
    cancel)        [[ "${1:-}" == "--pid" ]] && shift; cancel_pid "${1:-}";;
    terminate)     [[ "${1:-}" == "--pid" ]] && shift; terminate_pid "${1:-}";;
    help|-h|--help) usage ;;
    *) echo "Unknown command: $cmd"; usage; exit 2 ;;
  esac
else
  main_menu
fi
