#!/usr/bin/env python3
import sys, io

if len(sys.argv) != 4:
    print("usage: html_inject.py <into.html> <insert.html> <out.html>", file=sys.stderr)
    sys.exit(2)

into, insert, out = sys.argv[1:]
with open(into, 'r', encoding='utf-8') as f: base = f.read()
with open(insert, 'r', encoding='utf-8') as f: frag = f.read()

lower = base.lower()
idx = lower.rfind("</body>")
if idx == -1:
    joined = base + "\n<!-- EMBED START -->\n" + frag + "\n<!-- EMBED END -->\n"
else:
    joined = base[:idx] + "\n<!-- EMBED START -->\n" + frag + "\n<!-- EMBED END -->\n" + base[idx:]

with open(out, 'w', encoding='utf-8') as f: f.write(joined)
print(f"[ok] injected into {out}")
