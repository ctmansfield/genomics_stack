#!/usr/bin/env bash
set -Eeuo pipefail

# Where to look
REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK_DIRS=(
  "$REPO/scripts/tasks"
  "$REPO/scripts"
  "$REPO/tools"
)
echo "[audit] repo: $REPO"

# Grep helpers (quietly handle missing dirs)
gfind() {
  local d="$1"; shift || true
  [[ -d "$d" ]] || return 0
  grep -R -n -I --color=never "$@" "$d" || true
}

section() { printf '\n==== %s ====\n' "$*"; }
warn()    { printf '[warn] %s\n' "$*"; }
info()    { printf '[info] %s\n' "$*"; }
ok()      { printf '[ok]   %s\n' "$*"; }

# ---------- A) Identify task scripts touching VEP container/cache ----------
section "VEP container/cache references in scripts/tasks/ (and friends)"
PATTERN_VEP='ensembl[-_]vep|/opt/vep/.vep|INSTALL\.pl|CACHE_DIR|--cache|--database|--offline|Homo_sapiens\.GRCh|\.vep/homo_sapiens'
FOUND_VEP=0
for d in "${TASK_DIRS[@]}"; do
  gfind "$d" -E "$PATTERN_VEP" && FOUND_VEP=1
done
(( FOUND_VEP == 1 )) || warn "No explicit VEP/cache hits found under scripts/ (that may just mean tasks live elsewhere)."

# ---------- B) docker compose vs docker-compose ----------
section "docker compose usage (modern) vs docker-compose (legacy)"
FOUND_DC=0
FOUND_DCL=0
for d in "${TASK_DIRS[@]}"; do
  gfind "$d" -E '(^|[[:space:]])docker[[:space:]]+compose([[:space:]]|$)' && FOUND_DC=1
  gfind "$d" -E '(^|[[:space:]])docker-compose([[:space:]]|$)' && FOUND_DCL=1
done
(( FOUND_DC == 1 )) && ok "Modern 'docker compose' is referenced."
(( FOUND_DCL == 1 )) && warn "Legacy 'docker-compose' usage found (consider updating to 'docker compose')."
(( FOUND_DC == 0 && FOUND_DCL == 0 )) && info "No compose wrappers referenced in scripts/*."

# ---------- C) “install_all”, “rebuild”, “install”, “bootstrap” scripts ----------
section "Install / rebuild scripts and quick health checks"
FOUND_INSTALLS=$(find "$REPO" -maxdepth 2 -type f -iname '*install*' -o -iname '*rebuild*' -o -iname 'bootstrap*' 2>/dev/null || true)
if [[ -n "${FOUND_INSTALLS:-}" ]]; then
  echo "$FOUND_INSTALLS" | sed 's/^/[file] /'
else
  warn "No top-level install/rebuild/bootstrap scripts found at repo depth<=2."
fi

# quick lint for those files
if [[ -n "${FOUND_INSTALLS:-}" ]]; then
  echo "$FOUND_INSTALLS" | while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    hn=$(head -n1 "$f" 2>/dev/null || true)
    echo "---- $f"
    if [[ "$hn" =~ ^#! ]]; then
      ok "shebang: $hn"
    else
      warn "missing shebang (#!/usr/bin/env bash recommended) — add one."
    fi
    # pipefail/safety
    if grep -Eq 'set -[a-zA-Z]*e' "$f"; then ok "uses 'set -e'"; else warn "missing 'set -e'"; fi
    if grep -Eq 'pipefail' "$f"; then ok "uses 'pipefail'"; else warn "missing 'set -o pipefail'"; fi
    # docker compose modernization
    if grep -q 'docker-compose' "$f"; then warn "uses docker-compose (legacy)"; fi
    if grep -Eq 'ensemblorg/ensembl-vep|/opt/vep/.vep|INSTALL\.pl' "$f"; then
      ok "VEP container/cache logic present"
    fi
  done
fi

# ---------- D) obvious portability gotchas in scripts/* ----------
section "Portability checks (shebang, shell path, env loader, tabs)"
# shebang audit + /usr/bin/env availability
if [[ -x /usr/bin/env ]]; then
  ok "/usr/bin/env present; '#!/usr/bin/env bash' OK."
else
  warn "/usr/bin/env missing; prefer '#!/bin/bash' in *your* host."
fi

# audit all bash-ish scripts for shebang + set -euo pipefail
find "$REPO/scripts" -type f -maxdepth 2 \( -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.run' \) 2>/dev/null \
| while IFS= read -r f; do
  hn=$(head -n1 "$f" 2>/dev/null || true)
  [[ "$hn" =~ ^#! ]] || { printf '[warn] %s: missing shebang\n' "$f"; continue; }
  grep -Eq 'set -[^#\n]*e' "$f" || printf '[warn] %s: missing set -e\n' "$f"
  grep -Eq 'pipefail' "$f"     || printf '[warn] %s: missing pipefail\n' "$f"
done

# ---------- E) Where to configure the cache in your repo ----------
section "Suggested env anchors for VEP (if not already present)"
cat <<'EOF'
Add (or verify) these in env.d/app.env :
  CACHE_DIR=/mnt/nas_storage/vep/cache
  VEP_FASTA=/mnt/nas_storage/vep/reference/GRCh38.fa       # with .fai prebuilt
  VEP_IMAGE=ensemblorg/ensembl-vep:release_111.0
  ASSEMBLY=GRCh38

If you want rsID-only: use DB mode (no cache):
  VEP_MODE=database

If you want offline: you must supply coordinate inputs (VCF/TSV):
  VEP_MODE=offline
EOF

# ---------- F) Detect your vep.sh wrapper(s), if any ----------
section "vep.sh wrappers"
for d in "${TASK_DIRS[@]}"; do
  gfind "$d" -E 'scripts/vep/vep\.sh|vep\.sh|ensemblorg/ensembl-vep' | sed 's/^/[hit] /' || true
done

# ---------- G) Final notes ----------
section "Next steps"
cat <<'EOF'
- If you see 'docker-compose' anywhere, update to 'docker compose'.
- If tasks reference '/opt/vep/.vep' directly, prefer using CACHE_DIR and mount that path.
- For rsID lists, use DB mode (VEP --database); offline can't resolve rsIDs.
- Keep FASTA outside the cache and writable; pre-index with 'samtools faidx'.
EOF

exit 0
