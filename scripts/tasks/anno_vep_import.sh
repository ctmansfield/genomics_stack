#!/usr/bin/env bash
# shellcheck shell=bash

cmd_anno_vep_import(){
  local upload_id="${1:-}"; [[ -n "$upload_id" ]] || die "Usage: genomicsctl.sh anno-vep-import <upload_id>"
  local reports="${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}"
  local tsv="$reports/upload_${upload_id}/anno/upload_${upload_id}.vep.out.tsv"
  [[ -r "$tsv" ]] || die "TSV not found: $tsv (run: genomicsctl.sh anno-vep $upload_id)"

  say "[+] Ensuring schema/table"
  dc exec -T "$(pg_svc)" psql -U "$(pg_user)" -d "$(pg_db)" -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA IF NOT EXISTS anno;
CREATE TABLE IF NOT EXISTS anno.vep_tsv (
  upload_id  bigint,
  location   text, allele text,
  gene       text, symbol text,
  feature    text, consequence text, impact text, biotype text,
  existing_variation text, clin_sig text,
  af         text, gnomadg_af text,
  polyphen   text, sift text,
  hgvsc      text, hgvsp      text
);
CREATE INDEX IF NOT EXISTS vep_tsv_upload_idx ON anno.vep_tsv(upload_id);
CREATE INDEX IF NOT EXISTS vep_tsv_symbol_idx ON anno.vep_tsv(symbol);
CREATE INDEX IF NOT EXISTS vep_tsv_cons_idx   ON anno.vep_tsv(consequence);
SQL

  say "[+] Deleting old rows for upload_id=$upload_id"
  dc exec -T "$(pg_svc)" psql -U "$(pg_user)" -d "$(pg_db)" \
    -c "DELETE FROM anno.vep_tsv WHERE upload_id=$upload_id" >/dev/null

  say "[+] Loading TSV → anno.vep_tsv"
  # Strip CR, drop comments (##), skip the single header row, and prepend upload_id
  sed 's/\r$//' "$tsv" | \
  awk -v id="$upload_id" 'BEGIN{FS=OFS="\t"} /^#/ {next} header==0 {header=1; next} {print id, $0}' | \
  dc exec -T "$(pg_svc)" psql -U "$(pg_user)" -d "$(pg_db)" -v ON_ERROR_STOP=1 -c \
    "COPY anno.vep_tsv(upload_id,location,allele,gene,symbol,feature,consequence,impact,biotype,existing_variation,clin_sig,af,gnomadg_af,polyphen,sift,hgvsc,hgvsp) FROM STDIN WITH (FORMAT text, DELIMITER E'\t')"

  ok "Imported VEP rows for upload_id=$upload_id"
}

register_task "anno-vep-import" "Import VEP TSV into Postgres (anno.vep_tsv)" "cmd_anno_vep_import"
