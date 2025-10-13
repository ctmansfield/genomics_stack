#!/usr/bin/env bash
# Schema + globals backups with timestamp. Uses OUTDIR if set, else NAS path.

TS=$(date -u +%Y%m%d_%H%M%S)
OUTDIR="${OUTDIR:-/mnt/nas_storage/backups/postgres}"

# Try target dir; fall back to a local path if not writable.
mkdir -p "$OUTDIR" 2>/dev/null || {
  echo "[schema-backup] WARN: cannot write to $OUTDIR; using local fallback" >&2
  OUTDIR="${HOME}/_schema_backups"
  mkdir -p "$OUTDIR"
}

echo "[schema-backup] dumping schema to $OUTDIR..."
pg_dump --schema-only > "$OUTDIR/schema_${TS}.sql" 2>"$OUTDIR/schema_${TS}.log"
gzip -f "$OUTDIR/schema_${TS}.sql"
sha256sum "$OUTDIR/schema_${TS}.sql.gz" > "$OUTDIR/schema_${TS}.sql.gz.sha256"

echo "[schema-backup] dumping globals..."
pg_dumpall --globals-only > "$OUTDIR/globals_${TS}.sql" 2>"$OUTDIR/globals_${TS}.log"
gzip -f "$OUTDIR/globals_${TS}.sql"
sha256sum "$OUTDIR/globals_${TS}.sql.gz" > "$OUTDIR/globals_${TS}.sql.gz.sha256"

echo "[schema-backup] done → $OUTDIR"
