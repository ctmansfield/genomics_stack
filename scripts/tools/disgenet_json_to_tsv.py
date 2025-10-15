#!/usr/bin/env python3
import json, sys, csv
def pick(d,*keys):
    for k in keys:
        if k in d and d[k] not in (None,""): return d[k]
    return ""
def as_pmids(v):
    if v is None or v=="": return ""
    if isinstance(v,(list,tuple)): return ",".join(str(x) for x in v)
    return str(v)
if len(sys.argv)!=3:
    print("Usage: disgenet_json_to_tsv.py in.json out.tsv", file=sys.stderr); sys.exit(1)
inp, out = sys.argv[1], sys.argv[2]
with open(inp,"r",encoding="utf-8") as f: data=json.load(f)
rows=[]
if isinstance(data,list): rows=data
elif isinstance(data,dict):
    for key in ("items","result","data","content","rows"):
        if isinstance(data.get(key),list): rows=data[key]; break
    if not rows:
        for v in data.values():
            if isinstance(v,list) and v and isinstance(v[0],dict): rows=v; break
hdr=["geneSymbol","diseaseId","diseaseName","score","source","year","pmids"]
with open(out,"w",encoding="utf-8",newline="") as fo:
    w=csv.writer(fo,delimiter="\t"); w.writerow(hdr)
    for r in rows:
        gene=pick(r,"geneSymbol","gene_symbol","symbol","gene")
        did =pick(r,"diseaseId","disease_id","diseaseIdentifier","diseaseid","umls","umlsId")
        dnm =pick(r,"diseaseName","disease_name","disease")
        sc  =pick(r,"score","gdaScore","gdasc","DGNscore")
        src =pick(r,"source","dataSource","datasource")
        yr  =pick(r,"year")
        pm  =pick(r,"pmids","pubmedIds","pubMedIds","evidence")
        if not (gene or did or dnm): continue
        w.writerow([gene,did,dnm,sc,src,yr,as_pmids(pm)])
print(f"wrote {out}")
