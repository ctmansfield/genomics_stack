#!/usr/bin/env bash
# clinvar_sync.sh — Fetch & manage ClinVar VCF + TBI with rotation and a stable symlink.
# Defaults: GRCh38, weekly channel, keep last 6 releases.
# No 'set -euo pipefail' to align with your prefs.

BUILD="GRCh38"             # or GRCh37
CHANNEL="weekly"           # or monthly
DEST="/mnt/nas_storage/data/clinvar"
KEEP=6                     # number of dated releases to keep
WRITE_ENV=""               # e.g. /mnt/nas_storage/repos/genomics-stack/.env.clinvar
QUIET=0

usage() {
  cat <<EOF
Usage: $0 [--build GRCh38|GRCh37] [--channel weekly|monthly] [--dest DIR] [--keep N] [--write-env FILE] [--quiet]
Examples:
  $0 --build GRCh38 --channel weekly --dest /mnt/nas_storage/data/clinvar --keep 6
  $0 --build GRCh38 --channel monthly --write-env /mnt/nas_storage/repos/genomics-stack/.env.clinvar
EOF
}

msg(){ [ "$QUIET" -eq 0 ] && echo "[clinvar_sync] $*"; }

# --- arg parse ---
while [ $# -gt 0 ]; do
  case "$1" in
    --build) BUILD="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --keep) KEEP="$2"; shift 2;;
    --write-env) WRITE_ENV="$2"; shift 2;;
    --quiet) QUIET=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

# --- deps ---
need_bin() { command -v "$1" >/dev/null 2>&1 || { echo "[clinvar_sync] missing: $1"; exit 3; }; }
need_bin curl
need_bin awk
need_bin md5sum
# Optional but recommended
if command -v tabix >/dev/null 2>&1; then HAS_TABIX=1; else HAS_TABIX=0; fi

# --- base URLs (per ClinVar docs) ---
BASE="https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_${BUILD}/"     # weekly & latest
ARCH="${BASE}archive_2.0/"                                        # monthly archive

# locking (best-effort)
LOCKDIR="${DEST}/.${BUILD}.${CHANNEL}.lock"
mkdir -p "$DEST" 2>/dev/null
if mkdir "$LOCKDIR" 2>/dev/null; then
  trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT
else
  msg "another sync seems to be running (lock: $LOCKDIR)"; exit 1
fi

# --- figure out TARGET (date + URLs) ---
DATE_TAG=""
VCF_URL=""
MD5_URL=""
TBI_URL=""

if [ "$CHANNEL" = "weekly" ]; then
  # Parse top-level listing: pick newest clinvar_YYYYMMDD.vcf.gz; download 'clinvar.vcf.gz'
  page="$(curl -fsSL "$BASE")" || { echo "[clinvar_sync] cannot list $BASE"; exit 4; }
  DATE_TAG="$(printf "%s\n" "$page" | grep -Eo 'clinvar_[0-9]{8}\.vcf\.gz' | sed -E 's/.*_([0-9]{8}).*/\1/' | sort -nr | head -1)"
  [ -z "$DATE_TAG" ] && DATE_TAG="$(date +%Y%m%d)"
  VCF_URL="${BASE}clinvar.vcf.gz"
  MD5_URL="${VCF_URL}.md5"
  TBI_URL="${VCF_URL}.tbi"
else
  # monthly: find latest year then latest clinvar_YYYYMMDD.vcf.gz under archive_2.0/<year>/
  years="$(curl -fsSL "$ARCH" | grep -Eo 'href="20[0-9]{2}/"' | sed -E 's/.*"([0-9]{4})\/".*/\1/' | sort -nr)"
  latest_year="$(printf "%s\n" "$years" | head -1)"
  [ -z "$latest_year" ] && { echo "[clinvar_sync] cannot detect latest archive year at $ARCH"; exit 4; }
  page="$(curl -fsSL "${ARCH}${latest_year}/")" || { echo "[clinvar_sync] cannot list ${ARCH}${latest_year}/"; exit 4; }
  DATE_TAG="$(printf "%s\n" "$page" | grep -Eo 'clinvar_[0-9]{8}\.vcf\.gz' | sed -E 's/.*_([0-9]{8}).*/\1/' | sort -nr | head -1)"
  [ -z "$DATE_TAG" ] && { echo "[clinvar_sync] cannot detect latest monthly tag"; exit 4; }
  VCF_URL="${ARCH}${latest_year}/clinvar_${DATE_TAG}.vcf.gz"
  MD5_URL="${VCF_URL}.md5"
  TBI_URL="${VCF_URL}.tbi"
fi

msg "build=$BUILD channel=$CHANNEL date=$DATE_TAG"
msg "vcf=$VCF_URL"

# --- prepare paths ---
OUTROOT="${DEST}/${BUILD}/${DATE_TAG}"
mkdir -p "$OUTROOT" || { echo "[clinvar_sync] cannot create $OUTROOT"; exit 5; }
TMPDIR="$(mktemp -d "${OUTROOT}/.tmp.XXXXXX")" || { echo "[clinvar_sync] mktemp failed"; exit 5; }

VCF_TMP="${TMPDIR}/clinvar.vcf.gz"
TBI_TMP="${TMPDIR}/clinvar.vcf.gz.tbi"
MD5_TMP="${TMPDIR}/clinvar.vcf.gz.md5"

# --- download ---
msg "downloading VCF..."
curl -fL --retry 3 --retry-delay 2 -o "$VCF_TMP" "$VCF_URL" || { echo "[clinvar_sync] VCF download failed"; rm -rf "$TMPDIR"; exit 6; }
msg "downloading TBI..."
curl -fL --retry 3 --retry-delay 2 -o "$TBI_TMP" "$TBI_URL" || { echo "[clinvar_sync] TBI download failed"; rm -rf "$TMPDIR"; exit 6; }
msg "downloading MD5..."
curl -fL --retry 3 --retry-delay 2 -o "$MD5_TMP" "$MD5_URL" || { echo "[clinvar_sync] MD5 download failed"; rm -rf "$TMPDIR"; exit 6; }

# --- verify md5 ---
MD5_REMOTE="$(awk '{print $1; exit}' "$MD5_TMP")"
MD5_LOCAL="$(md5sum "$VCF_TMP" | awk '{print $1}')"
if [ -z "$MD5_REMOTE" ] || [ -z "$MD5_LOCAL" ] || [ "$MD5_REMOTE" != "$MD5_LOCAL" ]; then
  echo "[clinvar_sync] MD5 mismatch: remote=${MD5_REMOTE:-NA} local=${MD5_LOCAL:-NA}"
  rm -rf "$TMPDIR"; exit 7
fi
msg "md5 OK ($MD5_LOCAL)"

# --- optional: ensure index (remote TBI should suffice) ---
if [ "$HAS_TABIX" -eq 1 ]; then
  # Quick header check; if tabix balks, reindex locally
  if ! tabix -H "$VCF_TMP" >/dev/null 2>&1; then
    msg "remote index seems incompatible; reindexing locally"
    rm -f "$TBI_TMP"
    tabix -f -p vcf "$VCF_TMP" || { echo "[clinvar_sync] tabix failed"; rm -rf "$TMPDIR"; exit 8; }
  fi
fi

# --- finalize (atomic moves) ---
VCF_OUT="${OUTROOT}/clinvar.vcf.gz"
TBI_OUT="${OUTROOT}/clinvar.vcf.gz.tbi"
mv -f "$VCF_TMP" "$VCF_OUT" && mv -f "$TBI_TMP" "$TBI_OUT"
cp -f "$MD5_TMP" "${OUTROOT}/clinvar.vcf.gz.md5"
rm -rf "$TMPDIR"

# --- stable symlink ---
mkdir -p "${DEST}/${BUILD}/current" 2>/dev/null
ln -sfn "${OUTROOT}" "${DEST}/${BUILD}/current/.release"
ln -sfn "${DEST}/${BUILD}/current/.release/clinvar.vcf.gz" "${DEST}/${BUILD}/current/clinvar.vcf.gz"
ln -sfn "${DEST}/${BUILD}/current/.release/clinvar.vcf.gz.tbi" "${DEST}/${BUILD}/current/clinvar.vcf.gz.tbi"

# --- prune old ---
keep_n="${KEEP}"
if [ -n "$keep_n" ] && [ "$keep_n" -gt 0 ]; then
  # shellcheck disable=SC2012
  old="$(ls -1dt "${DEST}/${BUILD}"/2* 2>/dev/null | tail -n +$((keep_n+1)))"
  [ -n "$old" ] && { msg "pruning old releases:"; printf "  %s\n" $old; rm -rf $old; }
fi

# --- write env (optional) ---
if [ -n "$WRITE_ENV" ]; then
  mkdir -p "$(dirname "$WRITE_ENV")" 2>/dev/null
  echo "export CLINVAR_VCF='${DEST}/${BUILD}/current/clinvar.vcf.gz'" > "$WRITE_ENV"
  msg "wrote env to $WRITE_ENV"
fi

msg "done. current -> ${DEST}/${BUILD}/current/clinvar.vcf.gz"
