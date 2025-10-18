#!/usr/bin/env bash
# Repair the repo Makefile:
# - Remove older duplicate targets appearing before the "Re-declare default vars" marker
# - Remove any existing 'promote:' rule(s) and write a clean one (tabs, ON_ERROR_STOP)
# - Drop the old "lint-baseline-v1" block, keep "lint-hotfix-v1"
# - Ensure 'include mk/ctd_report.mk' exists once
# - Backup: Makefile.bak-YYYYmmddHHMMSS
# No strict mode; explicit checks. Does not exit the caller shell.

say(){ echo "[makefile-repair] $*" >&2; }
err(){ echo "[makefile-repair] ERROR: $*" >&2; return 1; }

repo_root="$(pwd)"
mf="$repo_root/Makefile"
[ -f "$mf" ] || { err "Makefile not found at $mf"; return 1 2>/dev/null || :; }

ts="$(date +%Y%m%d%H%M%S)"
bak="$mf.bak-$ts"
cp -f "$mf" "$bak" || { err "Could not create backup $bak"; return 1 2>/dev/null || :; }
say "Backup saved to $bak"

tmp="$mf.tmp.$ts"
cp -f "$mf" "$tmp" || { err "Could not stage temp file"; return 1 2>/dev/null || :; }

# 1) Drop the older lint-baseline-v1 block
sed -e '/^# --- added by lint-baseline-v1 ---/,/# <<< lint-baseline-v1/d' "$tmp" > "$tmp.1" \
  || { err "Failed to remove lint-baseline-v1 block"; return 1 2>/dev/null || :; }

# 2) Remove earlier duplicate target recipes (keep later ENV-aware ones)
#    We consider the region BEFORE the "Re-declare default vars (non-secret)" marker as "early".
#    Within this early region, drop target blocks for the known list.
targets_re='(vep-install|vep-verify|vep-update-cache|annotate|manifest|histogram|import-schema|import-verify|verify-dna|promote)'
awk -v targets_re="$targets_re" '
  BEGIN {
    in_early=1
    in_drop=0
  }
  # Marker that indicates start of the later section
  /^Re-declare default vars[[:space:]]*\(non-secret\)/ { in_early=0 }
  # Start of a target line
  /^[[:alnum:]_.-]+:[[:space:]]*$/ {
    # if we were dropping, stop dropping when we hit any new target line
    in_drop=0
    # figure if this target is one of the known names
    tl=$0
    sub(/:.*/,"",tl)
    if (in_early==1 && tl ~ targets_re) {
      in_drop=1
      next
    }
  }
  # If we are in a drop region (inside a target block we want to remove), skip lines
  in_drop==1 { next }
  { print }
' "$tmp.1" > "$tmp.2" || { err "Dedup pass failed"; return 1 2>/dev/null || :; }

# 3) Remove any remaining promote: blocks (wherever they are) and append a fixed one at the end
awk '
  BEGIN{ in_promote=0 }
  # detect start of promote block
  /^promote:[[:space:]]*$/ { in_promote=1; next }
  # if inside promote block, skip until blank line or next target line
  in_promote==1 {
    if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:alnum:]_.-]+:[[:space:]]*$/) {
      in_promote=0
      if ($0 ~ /^[[:alnum:]_.-]+:[[:space:]]*$/) { print $0 } else { print "" }
      next
    } else {
      next
    }
  }
  { print }
' "$tmp.2" > "$tmp.3" || { err "Promote removal pass failed"; return 1 2>/dev/null || :; }

# 4) Ensure include mk/ctd_report.mk exists once (append if missing)
if ! grep -qE '^[[:space:]]*include[[:space:]]+mk/ctd_report\.mk' "$tmp.3"; then
  printf '\n# --- CTD Report v2 targets ---\ninclude mk/ctd_report.mk\n' >> "$tmp.3"
  say "Appended: include mk/ctd_report.mk"
fi

# 5) Append a clean promote rule (tab-indented recipe)
cat >> "$tmp.3" <<'EOF_PROMOTE'

# --- fixed by makefile-repair (promote) ---
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

# 6) Finalize
mv -f "$tmp.3" "$mf" || { err "Could not finalize Makefile edits"; return 1 2>/dev/null || :; }
rm -f "$tmp" "$tmp.1" "$tmp.2" 2>/dev/null || true

say "Makefile repaired. Duplicate-target warnings should be gone and separators fixed."
say "If needed, restore with: cp -f '$bak' '$mf'"
