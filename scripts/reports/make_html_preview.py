# save as scripts/reports/make_html_preview.py
import csv, html, sys
src, dst = sys.argv[1], sys.argv[2]
rows = list(csv.reader(open(src, newline="")))
hdr, data = rows[0], rows[1:5000]
doc = ["<!doctype html><meta charset='utf-8'><title>Preview</title>",
       "<style>table{border-collapse:collapse;font:13px/1.35 system-ui}th,td{border:1px solid #ddd;padding:4px 6px;}</style>",
       "<table><thead><tr>",
       *[f"<th>{html.escape(x)}</th>" for x in hdr],
       "</tr></thead><tbody>"]
for r in data:
    doc.append("<tr>"+"".join(f"<td>{html.escape(c)}</td>" for c in r)+"</tr>")
doc.append("</tbody></table>")
open(dst,"w").write("".join(doc))
print("wrote", dst)
