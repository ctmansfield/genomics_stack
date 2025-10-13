#!/usr/bin/env python3
import os, csv, re, argparse, itertools
from typing import Optional
import psycopg

DDL = """
CREATE TABLE IF NOT EXISTS public.bio_processes(
  process_id text PRIMARY KEY,
  slug       text UNIQUE,
  label      text
);
CREATE TABLE IF NOT EXISTS public.gene_to_process(
  id          bigserial PRIMARY KEY,
  gene_symbol text NOT NULL,
  process_id  text NOT NULL REFERENCES public.bio_processes(process_id) ON DELETE CASCADE,
  role        text DEFAULT 'member',
  sign        integer DEFAULT 1,
  weight      double precision DEFAULT 0.6
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_gene_to_process_unique ON public.gene_to_process (gene_symbol, process_id);
CREATE TABLE IF NOT EXISTS public.process_to_system(
  process_id  text NOT NULL REFERENCES public.bio_processes(process_id) ON DELETE CASCADE,
  system_tag  text NOT NULL,
  weight      double precision DEFAULT 1.0,
  PRIMARY KEY (process_id, system_tag)
);
"""

def slugify(label: str) -> str:
    s = re.sub(r'[^A-Za-z0-9]+','-',label.strip()).strip('-').lower()
    return re.sub(r'-{2,}','-',s)[:200]

def canonicalize(cur, sym: str) -> str:
    try:
        cur.execute("SELECT public.canonical_gene_symbol(%s)", (sym,))
        r = cur.fetchone()
        if r and r[0]: return r[0]
    except Exception:
        pass
    return sym

def parse_gmt(path: str):
    out = []
    with open(path, 'r') as f:
        for line in f:
            if not line.strip() or line.startswith('#'): continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 3: continue
            name, desc, *genes = parts
            label = name.replace('REACTOME_','').replace('_',' ').title()
            url = desc if desc.startswith('http') else None
            genes = [g.strip() for g in genes if g.strip()]
            out.append((label, url, genes))
    return out

def chunked(it, n):
    import itertools
    it = iter(it)
    while True:
        chunk = list(itertools.islice(it, n))
        if not chunk: break
        yield chunk

def upsert_processes(cur, processes, system_tag: Optional[str]):
    cur.executemany(
        "INSERT INTO public.bio_processes (process_id, slug, label) VALUES (%s,%s,%s) "
        "ON CONFLICT (process_id) DO UPDATE SET slug=EXCLUDED.slug, label=EXCLUDED.label",
        processes
    )
    if system_tag:
        cur.executemany(
            "INSERT INTO public.process_to_system (process_id, system_tag, weight) VALUES (%s,%s,%s) "
            "ON CONFLICT (process_id, system_tag) DO NOTHING",
            [(pid, system_tag, 1.0) for (pid,_,_) in processes]
        )

def insert_edges(cur, edges, weight: float):
    for chunk in chunked(edges, 5000):
        cur.executemany(
            "INSERT INTO public.gene_to_process (gene_symbol, process_id, role, sign, weight) "
            "VALUES (%s,%s,'member',1,%s) "
            "ON CONFLICT (gene_symbol, process_id) DO NOTHING",
            [(g,p,weight) for (g,p) in chunk]
        )

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", required=True, type=int)
    ap.add_argument("--reactome", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--system-tag", default="reactome")
    ap.add_argument("--weight", type=float, default=0.6)
    ap.add_argument("--chunk", type=int, default=5000)
    args = ap.parse_args()

    if not os.path.exists(args.reactome):
        raise FileNotFoundError(args.reactome)
    sets = parse_gmt(args.reactome)
    print(f"[process] parsed {len(sets)} gene sets", flush=True)

    # Prefer PGURL if provided; otherwise empty DSN so libpq uses PG* envs/.pgpass
    pgurl = os.environ.get("PGURL")
    conn = psycopg.connect(pgurl) if pgurl else psycopg.connect("")

    processes = []
    edges = []
    with conn:
        with conn.cursor() as cur:
            cur.execute(DDL)
        with conn.cursor() as cur:
            for (label, url, genes) in sets:
                pid = slugify(label)
                processes.append((pid, pid, label))
            if processes:
                upsert_processes(cur, processes, args.system_tag)
            for (label, url, genes) in sets:
                pid = slugify(label)
                for g in genes:
                    edges.append((canonicalize(cur, g), pid))
            if edges:
                insert_edges(cur, edges, args.weight)

    os.makedirs(f"reports/upload_{args.upload_id}", exist_ok=True)
    sample = f"reports/upload_{args.upload_id}/process_memberships_sample.csv"
    with open(sample, "w", newline="") as f:
        import csv
        w = csv.writer(f)
        w.writerow(["process_id","label","gene_symbol","system_tag","weight"])
        label_by_pid = {pid: lbl for (pid,_,lbl) in processes}
        for (i,(g,p)) in enumerate(edges[:200]):
            w.writerow([p, label_by_pid.get(p,p), g, args.system_tag, args.weight])
    print(f"[process] wrote sample: {sample}", flush=True)
    print(f"[process] DONE: processes={len(processes)}, edges={len(edges)}", flush=True)

if __name__ == "__main__":
    main()
