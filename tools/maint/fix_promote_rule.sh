#!/usr/bin/env bash
# Fix the Makefile 'promote' rule: ensure TAB-indented recipe lines and a TAB-prefixed heredoc terminator.
# - Creates backup Makefile.bak-YYYYmmddHHMMSS
# - Removes any existing promote: blocks and appends a clean one at the end
# - No strict mode; does not exit the caller shell.

say(){ echo "[promote-fix] $*" >&2; }
err(){ echo "[promote-fix] ERROR: $*" >&2; return 1; }

mf="Makefile"
[ -f "$mf" ] || { err "Makefile not found in $(pwd)"; return 1 2>/dev/null || :; }

ts="$(date +%Y%m%d%H%M%S)"
bak="$mf.bak-$ts"
cp -f "$mf" "$bak" || { err "Could not create backup $bak"; return 1 2>/dev/null || :; }
say "Backup saved to $bak"

tmp="$mf.tmp-$ts"

# Remove any existing promote block(s)
awk '
  BEGIN{ in_promote=0 }
  /^promote:[[:space:]]*$/ { in_promote=1; next }          # skip the "promote:" line
  in_promote==1 {
    # end promote when blank line or next target line
    if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:alnum:]_.-]+:[[:space:]]*$/ || $0 ~ /^\.[[:alnum:]_.-]+:[[:space:]]*$/) {
      in_promote=0
      if ($0 ~ /^[[:alnum:]_.-]+:[[:space:]]*$/ || $0 ~ /^\.[[:alnum:]_.-]+:[[:space:]]*$/) print $0
      else print ""
      next
    } else { next }
  }
  { print }
' "$mf" > "$tmp" || { err "Failed removing old promote block(s)"; return 1 2>/dev/null || :; }

# Append a clean, tab-indented promote rule
# NOTE: The lines that appear to be indented below are REAL TABS, not spaces.
cat >> "$tmp" <<'EOF_PROMOTE'

# --- fixed by promote-fix ---
promote:
	@echo "[make] promote staging → main"
	psql "$(PGURL)" -v ON_ERROR_STOP=1 <<-'SQL'
	BEGIN;
	TRUNCATE public.annotated_variants;
	INSERT INTO public.annotated_variants
	SELECT * FROM public.annotated_variants_staging;
	TRUNCATE public.annotated_variants_staging;
	COMMIT;
	SQL
# --- end fix ---
EOF_PROMOTE

mv -f "$tmp" "$mf" || { err "Could not finalize Makefile edits"; return 1 2>/dev/null || :; }

say "Promote rule repaired with correct TABs and heredoc terminator."
say "Try:  make verify   (or your previous targets)"
