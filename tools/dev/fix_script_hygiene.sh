#!/usr/bin/env bash
set -Eeuo pipefail
fix() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local first
  first="$(head -n1 "$f" 2>/dev/null || true)"
  if [[ ! "$first" =~ ^#! ]]; then
    { printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'; cat "$f"; } >"$f.tmp" && mv "$f.tmp" "$f"
    echo "[fix] add shebang+strict: $f"
  else
    # ensure strict mode directly after shebang
    if ! grep -Eq 'set -E?e.*pipefail' "$f"; then
      awk 'NR==1{print; print "set -Eeuo pipefail"; next}1' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
      echo "[fix] add strict flags:  $f"
    fi
  fi
}

# From your auditor warnings (edit the list if you want fewer changes)
files=(
scripts/env.sh
scripts/tasks/anno_vep_import.sh
scripts/tasks/install_all.sh
scripts/tasks/vep_cache_install.sh
scripts/tasks/fix_perms.sh
scripts/tasks/report_top5.sh
scripts/tasks/apply_db_guards.sh
scripts/tasks/setup_dirs.sh
scripts/tasks/write_dotenv.sh
scripts/tasks/check_prev.sh
scripts/tasks/vep_selftest.sh
scripts/tasks/stack_up.sh
scripts/tasks/rebuild.sh
scripts/tasks/whoami.sh
scripts/tasks/pull_tools.sh
scripts/tasks/write_services.sh
scripts/tasks/up_stack.sh
scripts/tasks/fasta_install.sh
scripts/tasks/write_compose.sh
scripts/tasks/prereqs.sh
scripts/tasks/db_schema.sh
scripts/tasks/build_images.sh
scripts/tasks/report_extras.sh
scripts/tasks/anno_vep.sh
scripts/tasks/install_prereqs.sh
scripts/tasks/uploads.sh
scripts/tasks/claim.sh
scripts/tasks/write_env.sh
scripts/tasks/restart.sh
scripts/tasks/backup.sh
scripts/tasks/anno_vep_all.sh
scripts/tasks/vep_cache.sh
scripts/tasks/env.sh
scripts/tasks/risk_panel.sh
scripts/tasks/docker_install.sh
scripts/tasks/logs.sh
scripts/tasks/check.sh
)

for f in "${files[@]}"; do
  fix "$f"
done
