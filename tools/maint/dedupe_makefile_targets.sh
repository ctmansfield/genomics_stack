#!/usr/bin/env bash
# Cleans duplicate warnings in the repo Makefile without changing your env or shell.
# - Removes the older "lint-baseline-v1" block.
# - Repairs the corrupted 'promote' rule.
# - Makes a timestamped backup: Makefile.bak-YYYYmmddHHMMSS
# No strict mode; explicit checks only. No 'exit'.

say(){ echo "[makefile-dedupe] $*" >&2; }
fail(){ echo "[makefile-dedupe] ERROR: $*" >&2; return 1; }

repo_root="$(pwd)"
mf="$repo_root/Makefile"

[ -f "$mf" ] || { fail "Makefile not found at $mf"; return 1 2>/dev/null || :; }

ts="$(date +%Y%m%d%H%M%S)"
bak="$mf.bak-$ts"
cp -f "$mf" "$bak" || { fail "Could not create backup $bak"; return 1 2>/dev/null || :; }
say "Backup saved to $bak"

tmp="$mf.tmp.$ts"
cp -f "$mf" "$tmp" || { fail "Could not stage temp file"; return 1 2>/dev/null || :; }

# 1) Drop the older lint-baseline-v1 block (keep the newer lint-hotfix-v1)
#    Delete from line containing the start marker to the end marker line.
sed -e '/^# --- added by lint-baseline-v1 ---/,/# <<< lint-baseline-v1/d' "$tmp" > "$tmp.1" \
  || { fail "sed removal of lint-baseline-v1 failed"; return 1 2>/dev/null || :; }

# 2) Repair a corrupted 'promote' rule if present (we detect a broken token like '1000 4 24 ...')
#    Remove the entire existing promote: block and replace with a clean version.
awk '
  BEGIN{in_promote=0}
  /^promote:/{
    in_promote=1
    next
  }
  in_promote==1{
    # end the block on the first completely blank line or a line that looks like a new target (^\S.*:)
    if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:alnum:]_.-]+:[[:space:]]*$/){
      in_promote=2
    } else {
      next
    }
  }
  { print }
' "$tmp.1" > "$tmp.2"

# If we removed something, append the correct promote block once.
if ! grep -qE '^promote:' "$tmp.2"; then
  cat >> "$tmp.2" <<'EOF_PROMOTE'

# --- fixed by makefile-dedupe ---
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
fi

# 3) Write back
mv -f "$tmp.2" "$mf" || { fail "Could not finalize Makefile edits"; return 1 2>/dev/null || :; }
rm -f "$tmp" "$tmp.1" 2>/dev/null || true

say "Done. Warnings about overriding recipes should be reduced."
say "If anything looks off, restore with: cp -f '$bak' '$mf'"
