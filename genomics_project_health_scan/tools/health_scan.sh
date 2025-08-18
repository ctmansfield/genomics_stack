#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ -z "${MODE}" || "${MODE}" == "--help" || "${MODE}" == "-h" ]]; then
  cat <<'HLP'
Usage:
  health_scan.sh run [--no-docker] [--no-psql] [--no-vep]
  health_scan.sh --help

Environment (optional):
  HEALTH_OUT_DIR   Output dir for report (default: /root/genomics-stack/risk_reports/out/health_checks)
  COMPOSE_DIR      Docker compose dir for PG stack (default: /mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack)
  PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE for Postgres checks

HLP
  exit 0
fi

NO_DOCKER=0
NO_PSQL=0
NO_VEP=0
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker) NO_DOCKER=1 ;;
    --no-psql)   NO_PSQL=1 ;;
    --no-vep)    NO_VEP=1 ;;
  esac
  shift || true
done

HEALTH_OUT_DIR="${HEALTH_OUT_DIR:-/root/genomics-stack/risk_reports/out/health_checks}"
COMPOSE_DIR="${COMPOSE_DIR:-/mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack}"

mkdir -p "${HEALTH_OUT_DIR}"
ts="$(date +%Y%m%d_%H%M%S)"
report="${HEALTH_OUT_DIR}/project_health_scan_${ts}.txt"

section () {
  echo -e "\n=== $1 ===" | tee -a "$report"
}

note () {
  echo "[INFO] $*" | tee -a "$report"
}

warn () {
  echo "[WARN] $*" | tee -a "$report"
}

passfail () {
  local label="$1"; shift
  if "$@"; then
    echo "[OK] ${label}" | tee -a "$report"
    return 0
  else
    echo "[FAIL] ${label}" | tee -a "$report"
    return 1
  fi
}

# Start report
echo "Genomics Project Health Scan — $(date -Iseconds)" > "$report"

section "Directories"
req_dirs=(
  "/mnt/nas_storage/incoming"
  "/mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack"
  "/mnt/nas_storage/vep/cache"
  "/mnt/nas_storage/vep/reference"
  "/root/genomics-stack"
  "/root/genomics-stack/risk_reports/out"
  "/mnt/nas_storage/reports"
)
for d in "${req_dirs[@]}"; do
  if [[ -d "$d" ]]; then
    echo "[OK] dir exists: $d" | tee -a "$report"
  else
    echo "[FAIL] missing dir: $d" | tee -a "$report"
  fi
done

section "Key Files"
key_files=(
  "/root/genomics-stack/tools/vep_cache_bootstrap_guard.sh"
)
for f in "${key_files[@]}"; do
  if [[ -f "$f" ]]; then
    echo "[OK] file present: $f (mtime: $(date -r "$f" +%F' '%T))" | tee -a "$report"
  else
    echo "[FAIL] missing file: $f" | tee -a "$report"
  fi
done

section "Disk Usage"
{ df -h /mnt/nas_storage || true; du -sh /mnt/nas_storage/vep/cache 2>/dev/null || true; du -sh /mnt/nas_storage/vep/reference 2>/dev/null || true; } | tee -a "$report"

section "Incoming (latest 10)"
if [[ -d "/mnt/nas_storage/incoming" ]]; then
  ls -lt "/mnt/nas_storage/incoming" | head -n 12 | tee -a "$report" || true
else
  warn "incoming dir missing"
fi

if [[ $NO_DOCKER -eq 0 ]]; then
  section "Docker Compose (Postgres stack)"
  if [[ -d "$COMPOSE_DIR" ]]; then
    (
      cd "$COMPOSE_DIR"
      if command -v docker-compose >/dev/null 2>&1; then
        docker-compose ps | tee -a "$report" || warn "docker-compose ps failed"
      else
        docker compose ps | tee -a "$report" || warn "docker compose ps failed"
      fi
    )
  else
    warn "compose dir not found: $COMPOSE_DIR"
  fi
else
  note "docker checks disabled"
fi

if [[ $NO_PSQL -eq 0 ]]; then
  section "Postgres"
  if command -v psql >/dev/null 2>&1; then
    if [[ -n "${PGHOST:-}" && -n "${PGUSER:-}" ]]; then
      echo "\dt *.*" | psql -v ON_ERROR_STOP=0 -tA 2>&1 | tee -a "$report" || warn "psql listing failed"
      echo "select now();" | psql -v ON_ERROR_STOP=0 -tA 2>&1 | tee -a "$report" || true
      # Try generic counts if common tables exist
      for t in variants annotations; do
        echo "select 'table:'||'$t'||' rows=', count(*) from $t;" | psql -v ON_ERROR_STOP=0 -tA 2>&1 | tee -a "$report" || true
      done
    else
      warn "PG env not set; skipping psql checks"
    fi
  else
    warn "psql not installed"
  fi
else
  note "psql checks disabled"
fi

if [[ $NO_VEP -eq 0 ]]; then
  section "VEP"
  if command -v vep >/dev/null 2>&1; then
    vep --version 2>&1 | tee -a "$report" || true
  else
    warn "vep not on PATH"
  fi
  if [[ -d "/mnt/nas_storage/vep/cache" ]]; then
    find /mnt/nas_storage/vep/cache -maxdepth 1 -type d -printf "%f\n" | sort | tee -a "$report"
  fi
else
  note "VEP checks disabled"
fi

section "Reports Dir"
if [[ -d "/root/genomics-stack/risk_reports/out" ]]; then
  ls -lt "/root/genomics-stack/risk_reports/out" | head -n 20 | tee -a "$report" || true
fi

echo -e "\n[RESULT] Report written: $report"
echo "$report"
