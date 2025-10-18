#!/usr/bin/env bash
# Normalize Makefile to fix "missing separator" by ensuring TAB-indented recipe lines.
# - Backup: Makefile.bak-YYYYmmddHHMMSS
# - Convert CRLF -> LF
# - Convert leading spaces in recipe lines to a single TAB (only within target recipes)
# - Does not modify variable-assignment lines or non-recipe blocks
# - No strict mode; does not exit the caller shell.

say(){ echo "[makefile-fix] $*" >&2; }
err(){ echo "[makefile-fix] ERROR: $*" >&2; return 1; }

mf="Makefile"
[ -f "$mf" ] || { err "Makefile not found in $(pwd)"; return 1 2>/dev/null || :; }

ts="$(date +%Y%m%d%H%M%S)"
bak="$mf.bak-$ts"
cp -f "$mf" "$bak" || { err "Could not create backup $bak"; return 1 2>/dev/null || :; }
say "Backup saved to $bak"

tmp="$mf.tmp-$ts"

# 1) Convert CRLF to LF and strip stray non-breaking spaces
#    (NBSP often creeps in via copy/paste and breaks make)
python3 - "$mf" "$tmp" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
# Replace CRLF and CR with LF
data = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
# Replace NBSP and weird unicode spaces with normal spaces
data = data.replace(b'\xc2\xa0', b' ')  # NBSP
open(dst, 'wb').write(data)
PY

[ -s "$tmp" ] || { err "CRLF normalization failed"; return 1 2>/dev/null || :; }

# 2) Convert leading spaces within recipe blocks to TAB
#    Heuristics:
#    - target line: ^([A-Za-z0-9_.-]|\.PHONY).+:
#    - NOT a var assignment line: ^[A-Za-z_][A-Za-z0-9_]*\s*(\?=|:=|\+=|=)
#    - When inside recipe block, any non-blank line that doesn't start with TAB and doesn't look like a new target => convert leading spaces to TAB
awk '
  # Helper to decide if line is a variable assignment (not a rule)
  function is_assign(line) {
    return (line ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\?=|:=|\+=|=)/)
  }
  # Helper to decide if line starts a target (rule) definition
  function is_target(line) {
    # e.g., name: deps or .PHONY: names
    return (line ~ /^[[:alnum:]_.-]+[[:space:]]*:/ || line ~ /^\.[[:alnum:]_.-]+[[:space:]]*:/)
  }
  # Helper to decide if line is a new stanza start (target or assignment)
  function is_stanza_start(line) {
    return is_target(line) || is_assign(line)
  }

  {
    raw = $0
    # Track whether we are inside a recipe block
    # We enter a recipe block right after a target line; we leave on blank line or next stanza start
    if (is_target(raw) && !is_assign(raw)) {
      in_recipe = 1
      print raw
      next
    }

    if (in_recipe) {
      # If line is empty or starts a new stanza, we end recipe mode
      if (raw ~ /^[[:space:]]*$/ || is_stanza_start(raw)) {
        in_recipe = 0
        print raw
        next
      }
      # If this is a recipe line and does not start with TAB, convert leading spaces to one TAB
      if (raw !~ /^\t/ && raw ~ /^[[:space:]]+/) {
        sub(/^[[:space:]]+/, "\t", raw)
        print raw
        next
      }
      # Otherwise, print as-is
      print raw
      next
    }

    # Default (outside recipe)
    print raw
  }
' "$tmp" > "$mf" || { err "Recipe TAB normalization failed"; return 1 2>/dev/null || :; }

say "Done. Try your make target again."
say "If anything looks off, restore with: cp -f '$bak' '$mf'"
