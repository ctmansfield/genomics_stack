#!/usr/bin/env bash
# Minimal, safe ShellCheck fixes bundle
# Usage: ./apply.sh /path/to/your/repo
set -euo pipefail

REPO="${1:-.}"
cd "$REPO"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root=".patch_backups/${ts}"

log(){ printf "[-] %s\n" "$*" >&2; }
ok(){ printf "[ok] %s\n" "$*"; }
changed(){ printf "[fix] %s\n" "$*"; }
skip(){ printf "[skip] %s\n" "$*"; }

backup(){
  local rel="$1"
  mkdir -p "${backup_root}/$(dirname "$rel")"
  cp -a "$rel" "${backup_root}/${rel}"
}

ensure_file(){
  local f="$1"
  [[ -f "$f" ]] || { skip "$f (missing)"; return 1; }
  return 0
}

# Replace a single-line 'local var="...$(...)..."' with 2 lines (declare then assign)
split_local_assign(){
  local file="$1" var="$2" pattern="$3" assign="$4"
  ensure_file "$file" || return 0
  if grep -qE "$pattern" "$file"; then
    backup "$file"
    awk -v v="$var" -v a="$assign" '
      $0 ~ /'"$pattern"'/ {
        print "  local " v;
        print "  " v "=" a;
        next
      } { print }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    changed "$file: split local $var assignment"
  else
    skip "$file: pattern not found for $var"
  fi
}

insert_above_line_once(){
  # Insert a line above the first match if that exact line is not already present immediately above
  local file="$1" match_re="$2" insert_text="$3"
  ensure_file "$file" || return 0
  if awk -v r="$match_re" -v t="$insert_text" '
        $0 ~ r {
          if (prev != t){ print t }
          print; seen=1; next
        }
        { if (NR>1) prev=$0; print }
        END{ if (!seen) exit 1 }
      ' "$file" > "$file.tmp"; then
    backup "$file"
    mv "$file.tmp" "$file"
    changed "$file: inserted directive above match"
  else
    skip "$file: match not found for insertion"
    rm -f "$file.tmp" || true
  fi
}

replace_line_matching(){
  local file="$1" match_re="$2" replacement_block="$3"
  ensure_file "$file" || return 0
  if grep -qE "$match_re" "$file"; then
    backup "$file"
    awk -v r="$match_re" -v repl="$replacement_block" '
      $0 ~ r && !done {
        print repl;
        done=1;
        next
      } { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    changed "$file: replaced matching line/block"
  else
    skip "$file: no matching line to replace"
  fi
}

replace_regex_in_file(){
  local file="$1" sed_expr="$2"
  ensure_file "$file" || return 0
  if grep -Eq "$(echo "$sed_expr" | sed -E 's#^s/(.+)/.*#\\1#')" "$file"; then
    backup "$file"
    sed -E -i "$sed_expr" "$file"
    changed "$file: regex replacement applied"
  else
    skip "$file: regex search not found"
  fi
}

strip_leading_blank_lines(){
  local file="$1"
  ensure_file "$file" || return 0
  backup "$file"
  awk 'BEGIN{started=0}
       { if (!started){ if ($0 ~ /^[[:space:]]*$/) next; started=1 }
         print
       }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  changed "$file: stripped leading blank lines (shebang to line 1)"
}

# ---- Specific fixes ----

# 1) scripts/dev/gitctl.sh: SC2155 (local+assign)
split_local_assign "scripts/dev/gitctl.sh" "safety" 'local[[:space:]]+safety="[[:alnum:]_-]+-\$\([[:space:]]*now_utc[[:space:]]*\)"' '"safety-rollback-\\$(now_utc)"'

# 2) scripts/env.sh: SC2034 (unused vars) -> annotate, SC2046 (word splitting) -> robust export
insert_above_line_once "scripts/env.sh" '^[[:space:]]*COMPOSE_FILE=' '# shellcheck disable=SC2034'
insert_above_line_once "scripts/env.sh" '^[[:space:]]*DB_HOST=' '# shellcheck disable=SC2034'
insert_above_line_once "scripts/env.sh" '^[[:space:]]*DB_PORT=' '# shellcheck disable=SC2034'
insert_above_line_once "scripts/env.sh" '^[[:space:]]*PGUSER=' '# shellcheck disable=SC2034'
insert_above_line_once "scripts/env.sh" '^[[:space:]]*PGPASS=' '# shellcheck disable=SC2034'
insert_above_line_once "scripts/env.sh" '^[[:space:]]*PGDB='   '# shellcheck disable=SC2034'

replace_line_matching "scripts/env.sh" \
'export[[:space:]]*\$\(.+POSTGRES_USER\|POSTGRES_PASSWORD\|POSTGRES_DB\|UPLOAD_TOKEN.+' \
'  # Read specific keys from .env without word-splitting issues
  while IFS="=" read -r k v; do
    case "$k" in
      POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_DB|UPLOAD_TOKEN)
        export "$k=$v"
        ;;
    esac
  done < "$STACK_DIR/.env"'

# 3) scripts/lib/common.sh: SC1090 dynamic source
insert_above_line_once "scripts/lib/common.sh" '[[:space:]]\.[[:space:]]+"\$ENV_FILE"' '# shellcheck source=/dev/null'

# 4) scripts/tasks/fasta_install.sh: SC2155
split_local_assign "scripts/tasks/fasta_install.sh" "gz" 'local[[:space:]]+gz="[^"]+"' '"$CACHE_ROOT/$(basename "$FASTA_URL")"'

# 5) scripts/tasks/report_pdf_any.sh: SC2046 -> quote substitutions
replace_regex_in_file "scripts/tasks/report_pdf_any.sh" 's#--print-to-pdf=/data/\$\((basename[[:space:]]+"?\$pdf"?)[^)]*\)[[:space:]]+file:///data/\$\((basename[[:space:]]+"?\$html"?)[^)]*\)#--print-to-pdf="/data/$(basename "$pdf")" "file:///data/$(basename "$html")"#'

# 6) scripts/tasks/vep_cache_install.sh: SC2155 + SC2316
split_local_assign "scripts/tasks/vep_cache_install.sh" "tar" 'local[[:space:]]+tar="[^"]+"' '"$CACHE_ROOT/tmp/$(basename "$ENSEMBL_CACHE_URL")"'
replace_regex_in_file "scripts/tasks/vep_cache_install.sh" 's#^[[:space:]]*local[[:space:]]+remote[[:space:]]+local[[:space:]]*$#  local remote local_path#'

# 7) scripts/tasks/report_top5.sh: SC1128 + here-doc quoting issues
strip_leading_blank_lines "scripts/tasks/report_top5.sh"
replace_regex_in_file "scripts/tasks/report_top5.sh" 's#sudo[[:space:]]+bash[[:space:]]+-lc[[:space:]]+"cat[[:space:]]+>..\\$html..[[:space:]]+<<..HTML.."#sudo tee "$html" >/dev/null <<'\''HTML'\''#g'
replace_regex_in_file "scripts/tasks/report_top5.sh" 's#sudo[[:space:]]+bash[[:space:]]+-lc[[:space:]]+"cat[[:space:]]+>>..\\$html..[[:space:]]+<<..HTML.."#sudo tee -a "$html" >/dev/null <<'\''HTML'\''#g'
replace_regex_in_file "scripts/tasks/report_top5.sh" 's#^HTML"$#HTML#g'

# 8) tools/env/load_env.sh: SC1090 dynamic source
insert_above_line_once "tools/env/load_env.sh" '[[:space:]]source[[:space:]]+"\$f"' '# shellcheck source=/dev/null'

# 9) tools/repo_upgrade_menu.sh: SC2155 split local assignment
split_local_assign "tools/repo_upgrade_menu.sh" "dir" 'local[[:space:]]+dir="[^"]*"' '"$BACKUP_DIR/$patch/$(dirname "$rel")"'

# 10) tools/stage_sample.sh: SC2120 allow function to take 0 args without warning
insert_above_line_once "tools/stage_sample.sh" '^[[:space:]]*PSQL\(\)' '# shellcheck disable=SC2120'

ok "All done. Backups saved under $backup_root"
