#!/usr/bin/env bash
# shellcheck shell=bash

: "${VEP_IMAGE:=ensemblorg/ensembl-vep}"

_psql_bool(){ dc exec -T "$(pg_svc)" psql -U "$(pg_user)" -d "$(pg_db)" -Atc "$1"; }

_pick_vep_tag(){
  local t
  for t in release_114.4 release_114.3 release_114.2 release_114.1 release_114 latest; do
    if docker image inspect "${VEP_IMAGE}:$t" >/dev/null 2>&1 || docker pull "${VEP_IMAGE}:$t" >/dev/null 2>&1; then
      echo "$t"; return 0
    fi
  done
  return 1
}

_detect_fasta(){
  local cache="$1" p
  for p in \
    "$cache"/homo_sapiens/*GRCh38*/Homo_sapiens.GRCh38*.fa \
    "$cache"/homo_sapiens/*GRCh38*/Homo_sapiens.GRCh38*.fa.gz \
    "$cache"/Homo_sapiens.GRCh38*.fa \
    "$cache"/Homo_sapiens.GRCh38*.fa.gz; do
    [[ -f "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

_build_export_sql(){
  local upload_id="$1"
  local has_variants has_geno has_sac
  has_variants=$(_psql_bool "select exists (select 1 from information_schema.tables where table_schema='public' and table_name='variants')")
  has_geno=$(_psql_bool "select exists (select 1 from information_schema.tables where table_schema='public' and table_name='genotypes')")
  has_sac=$(_psql_bool  "select exists (select 1 from information_schema.tables where table_schema='public' and table_name='staging_array_calls')")
  [[ "$has_variants" == "t" ]] || return 1

  local g_has_upload g_has_sample
  g_has_upload=$(_psql_bool "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='genotypes' and column_name='upload_id')")
  g_has_sample=$(_psql_bool "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='genotypes' and column_name='sample_id')")

  local has_uploads u_has_upload u_has_sample
  has_uploads=$(_psql_bool "select exists (select 1 from information_schema.tables where table_schema='public' and table_name='uploads')")
  u_has_upload=$(_psql_bool "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='uploads' and column_name='upload_id')")
  u_has_sample=$(_psql_bool "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='uploads' and column_name='sample_id')")

  if [[ "$has_geno" == "t" && "$g_has_upload" == "t" ]]; then
    cat <<'SQL'
SELECT CASE WHEN v.chrom ~ '^chr' THEN substring(v.chrom from 4) ELSE v.chrom END AS chrom,
       v.pos, COALESCE(v.rsid,'rs0') AS id, v.ref, v.alt
FROM public.genotypes g
JOIN public.variants v ON v.variant_id = g.variant_id
WHERE g.upload_id = __UPLOAD_ID__
  AND v.chrom IS NOT NULL AND v.pos IS NOT NULL AND v.ref IS NOT NULL AND v.alt IS NOT NULL
SQL
    return 0
  fi

  if [[ "$has_geno" == "t" && "$g_has_sample" == "t" && "$has_uploads" == "t" && "$u_has_upload" == "t" && "$u_has_sample" == "t" ]]; then
    cat <<'SQL'
SELECT CASE WHEN v.chrom ~ '^chr' THEN substring(v.chrom from 4) ELSE v.chrom END AS chrom,
       v.pos, COALESCE(v.rsid,'rs0') AS id, v.ref, v.alt
FROM public.genotypes g
JOIN public.uploads u ON u.sample_id = g.sample_id
JOIN public.variants v ON v.variant_id = g.variant_id
WHERE u.upload_id = __UPLOAD_ID__
  AND v.chrom IS NOT NULL AND v.pos IS NOT NULL AND v.ref IS NOT NULL AND v.alt IS NOT NULL
SQL
    return 0
  fi

  if [[ "$has_sac" == "t" ]]; then
    local sac_has_rsid sac_has_chr sac_has_pos
    sac_has_rsid=$(_psql_bool "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='staging_array_calls' and column_name='rsid')")
    sac_has_chr=$(_psql_bool  "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='staging_array_calls' and column_name='chrom')")
    sac_has_pos=$(_psql_bool  "select exists (select 1 from information_schema.columns where table_schema='public' and table_name='staging_array_calls' and column_name='pos')")
    if [[ "$sac_has_rsid" == "t" ]]; then
      cat <<'SQL'
SELECT CASE WHEN v.chrom ~ '^chr' THEN substring(v.chrom from 4) ELSE v.chrom END AS chrom,
       v.pos, COALESCE(v.rsid,'rs0') AS id, v.ref, v.alt
FROM public.staging_array_calls s
JOIN public.variants v ON v.rsid = s.rsid
WHERE s.upload_id = __UPLOAD_ID__
  AND v.chrom IS NOT NULL AND v.pos IS NOT NULL AND v.ref IS NOT NULL AND v.alt IS NOT NULL
SQL
      return 0
    fi
    if [[ "$sac_has_chr" == "t" && "$sac_has_pos" == "t" ]]; then
      cat <<'SQL'
SELECT CASE WHEN s.chrom ~ '^chr' THEN substring(s.chrom from 4) ELSE s.chrom END AS chrom,
       s.pos, COALESCE(v.rsid,'rs0') AS id, v.ref, v.alt
FROM public.staging_array_calls s
JOIN public.variants v
  ON (CASE WHEN s.chrom ~ '^chr' THEN substring(s.chrom from 4) ELSE s.chrom END) = v.chrom
 AND s.pos = v.pos
WHERE s.upload_id = __UPLOAD_ID__
  AND v.ref IS NOT NULL AND v.alt IS NOT NULL
SQL
      return 0
    fi
  fi
  return 1
}

cmd_anno_vep(){
  local upload_id="${1:-}"; [[ -n "$upload_id" ]] || die "Usage: genomicsctl.sh anno-vep <upload_id>"
  local reports="${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}"
  local cache="${CACHE_ROOT:-/mnt/nas_storage/genomics-stack/vep_cache}"
  local outdir="$reports/upload_${upload_id}/anno"; mkdir -p "$outdir"

  local vcf_in="$outdir/upload_${upload_id}.vep.in.vcf"
  local vcf_out="$outdir/upload_${upload_id}.vep.out.vcf"
  local tsv_out="$outdir/upload_${upload_id}.vep.out.tsv"

  say "[+] Building export SQL for upload_id=$upload_id"
  local sql; sql="$(_build_export_sql "$upload_id")" || die "No compatible source to export variants."
  sql="${sql//__UPLOAD_ID__/$upload_id}"

  say "[+] Exporting to VCF: $vcf_in"
  {
    echo '##fileformat=VCFv4.2'
    echo '##reference=GRCh38'
    echo -e '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO'
    dc exec -T "$(pg_svc)" psql -U "$(pg_user)" -d "$(pg_db)" -Atc \
      "WITH rows AS ($sql)
       SELECT chrom || E'\t' || pos || E'\t' || id || E'\t' || ref || E'\t' || alt || E'\t.\tPASS\t.' FROM rows"
  } > "$vcf_in"
  ok "VCF rows: $(($(wc -l < "$vcf_in") - 3))"

  say "[+] Resolving VEP image…"
  local vep_tag="${VEP_IMAGE_TAG:-}"; [[ -n "$vep_tag" ]] || vep_tag="$(_pick_vep_tag)" || die "No suitable ${VEP_IMAGE} tag found."

  say "[+] Detecting FASTA under cache: $cache"
  local fasta_host; if fasta_host="$(_detect_fasta "$cache")"; then
    ok "FASTA: $fasta_host"
    local fasta_in_container="/opt/vep/.vep${fasta_host#$cache}"
    FASTA_ARGS=( --fasta "$fasta_in_container" )
  else
    warn "No FASTA found; letting VEP auto-discover from cache."
    FASTA_ARGS=()
  fi

  # Always stream input and capture output (robust across NFS/noexec/root_squash)
  say "[+] VEP (${VEP_IMAGE}:$vep_tag) → VCF (stdin/stdout)"
  cat "$vcf_in" | docker run --rm -i -v "$cache":/opt/vep/.vep:ro "${VEP_IMAGE}:$vep_tag" \
    vep --offline --cache --dir_cache /opt/vep/.vep \
        --species homo_sapiens --assembly GRCh38 \
        "${FASTA_ARGS[@]}" \
        --input_file /dev/stdin \
        --vcf --output_file /dev/stdout \
        --everything --no_stats --force_overwrite --fork 4 --buffer_size 5000 \
    > "$vcf_out"
  ok "VEP VCF: $vcf_out"

  say "[+] VEP (${VEP_IMAGE}:$vep_tag) → TSV (stdin/stdout)"
  cat "$vcf_in" | docker run --rm -i -v "$cache":/opt/vep/.vep:ro "${VEP_IMAGE}:$vep_tag" \
    vep --offline --cache --dir_cache /opt/vep/.vep \
        --species homo_sapiens --assembly GRCh38 \
        "${FASTA_ARGS[@]}" \
        --input_file /dev/stdin \
        --tab --output_file /dev/stdout \
        --fields "Location,Allele,Gene,SYMBOL,Feature,Consequence,IMPACT,BIOTYPE,Existing_variation,CLIN_SIG,AF,gnomADg_AF,PolyPhen,SIFT,HGVSc,HGVSp" \
        --no_stats --force_overwrite --fork 4 --buffer_size 5000 \
    > "$tsv_out"
  ok "VEP TSV: $tsv_out"
}

register_task "anno-vep" "Export variants for an upload and run VEP (VCF+TSV)" "cmd_anno_vep"
