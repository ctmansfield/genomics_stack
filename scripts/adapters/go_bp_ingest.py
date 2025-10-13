#!/usr/bin/env python3
"""
GO:BP (Gene Ontology – Biological Process) ingest (symbol-based).

- Parses a GOA/GAF file (human) and keeps only Aspect 'P' (BP).
- Upserts processes into bio_processes with NUMERIC process_id (auto-assign),
  storing GO term as the slug "go-bp-<GO_0000000>" and label "<GO:0000000>".
- Inserts gene_to_process edges using a resolver (override > direct HGNC > unambiguous alias).
- Optionally attempts to map each process to a system_tag in process_to_system (best-effort).
- Writes a small sample CSV under reports/upload_<id>/go_bp_memberships_sample.csv.

CLI:
  python3 scripts/adapters/go_bp_ingest.py \
    --upload-id 2 \
    --gaf /mnt/nas_storage/ref/processes/go/goa_human.gaf \
    --version "GOA Human 2025-09-30" \
    --weight 0.55 --system-tag go_bp --chunk 5000 --progress-every 50000
"""

import os, sys, csv, argparse, itertools, psycopg
from collections import defaultdict
from typing import Dict, Set, Iterable, List, Tuple

def ensure_dir(p: str) -> None:
    os.makedirs(p, exist_ok=True)

def chunked(it: Iterable, n: int):
    it = iter(it)
    while True:
        chunk = list(itertools.islice(it, n))
        if not chunk:
            return
        yield chunk

def next_numeric_id(cur) -> int:
    cur.execute("SELECT COALESCE(MAX(process_id), 0) + 1 FROM public.bio_processes")
    return int(cur.fetchone()[0])

def ensure_process_numeric(cur, slug: str, label: str) -> int:
    cur.execute("SELECT process_id FROM public.bio_processes WHERE slug=%s", (slug,))
    r = cur.fetchone()
    if r: return int(r[0])
    pid = next_numeric_id(cur)
    cur.execute(
        "INSERT INTO public.bio_processes(process_id, slug, label) VALUES (%s,%s,%s)",
        (pid, slug, label)
    )
    return pid

def upsert_processes(cur, go_sets: Dict[str, Set[str]], system_tag: str) -> Dict[str, int]:
    idmap: Dict[str,int] = {}
    for go_id in go_sets.keys():
        slug = f"go-bp-{go_id.replace(':','_').lower()}"
        label = f"{go_id}"
        pid = ensure_process_numeric(cur, slug, label)
        idmap[slug] = pid
    # best-effort system mapping
    if system_tag:
        rows = [(pid, system_tag, 1.0) for pid in idmap.values()]
        try:
            cur.executemany("""
              INSERT INTO public.process_to_system(process_id, system_tag, weight)
              VALUES (%s,%s,%s)
              ON CONFLICT (process_id, system_tag) DO NOTHING
            """, rows)
        except Exception as e:
            print(f"[go-bp] WARN: process_to_system map skipped ({e.__class__.__name__}: {e})", flush=True)
    return idmap

def resolve_symbol(cur, sym: str) -> str:
    # Resolver precedence: overrides > exact HGNC > unambiguous alias; else raw sym
    cur.execute("""
      SELECT canon FROM (
        SELECT o.canonical AS canon, 1 AS ord
        FROM public.gene_identifier_overrides o
        WHERE o.alias = %s

        UNION ALL
        SELECT gi.gene_symbol, 2
        FROM public.gene_identifiers gi
        WHERE gi.gene_symbol = %s

        UNION ALL
        SELECT u.canonical, 3
        FROM public.v_gene_alias_unambiguous u
        WHERE u.alias = %s
      ) s
      ORDER BY ord
      LIMIT 1
    """, (sym, sym, sym))
    r = cur.fetchone()
    return r[0] if r else sym

def upsert_edges(cur, edges: List[Tuple[str,int,float]], page_size: int):
    # Ensure target genes exist if FK to gene_catalog is present (safe no-op otherwise)
    try:
        cur.executemany("""
          INSERT INTO public.gene_catalog(gene_symbol)
          VALUES (%s)
          ON CONFLICT DO NOTHING
        """, [(g,) for g,_,_ in edges])
    except Exception:
        pass

    for page in chunked(edges, page_size):
        cur.executemany("""
          INSERT INTO public.gene_to_process(gene_symbol, process_id, role, sign, weight)
          VALUES (%s,%s,'member',1,%s)
          ON CONFLICT (gene_symbol, process_id) DO UPDATE
          SET weight = EXCLUDED.weight
        """, page)

def parse_gaf(path: str) -> Dict[str, Set[str]]:
    go_sets: Dict[str,Set[str]] = defaultdict(set)
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if not line or line.startswith('!'):  # header/comment
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 15:
                continue
            db, db_obj_id, symbol, qualifier, go_id, ref, ev, withfrom, aspect = parts[0:9]
            taxon = parts[12] if len(parts) > 12 else ""
            if aspect != 'P':
                continue
            if 'taxon:9606' not in taxon:
                continue
            sym = symbol.strip()
            if not sym or sym == '-':
                continue
            go_sets[go_id].add(sym)
    return go_sets

def write_sample(report_dir: str, sample_rows: List[Tuple[str,str]]):
    ensure_dir(report_dir)
    out = os.path.join(report_dir, "go_bp_memberships_sample.csv")
    with open(out, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(["gene_symbol","go_slug"])
        w.writerows(sample_rows[:200])
    print(f"[go-bp] wrote sample: {out}", flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", required=True, type=int)
    ap.add_argument("--gaf", required=True, help="GOA/GAF file (human)")
    ap.add_argument("--version", required=True)
    ap.add_argument("--weight", type=float, default=0.55)
    ap.add_argument("--system-tag", default="go_bp")
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    # load/parse
    print("[go-bp] parsing GAF…", flush=True)
    go_sets = parse_gaf(args.gaf)
    if not go_sets:
        print("[go-bp] no GO:BP rows parsed; check file/aspect/taxon filters", flush=True)
        sys.exit(1)
    print(f"[go-bp] parsed {len(go_sets)} GO:BP terms", flush=True)

    # connect via env (PG* or PGURL)
    pgurl = os.environ.get("PGURL", "")
    with psycopg.connect(pgurl) as conn:
        with conn.cursor() as cur:
            # Upsert processes (+ optional mapping)
            idmap = upsert_processes(cur, go_sets, args.system_tag)

            # Build edges — resolve symbols deterministically
            edges: List[Tuple[str,int,float]] = []
            seen = set()
            n = 0
            for go_id, syms in go_sets.items():
                slug = f"go-bp-{go_id.replace(':','_').lower()}"
                pid = idmap[slug]
                for s in syms:
                    cur_sym = resolve_symbol(cur, s)
                    key = (cur_sym, pid)
                    if key in seen: 
                        continue
                    seen.add(key)
                    edges.append((cur_sym, pid, args.weight))
                n += len(syms)
                if n % args.progress_every == 0:
                    print(f"[go-bp] parsed symbols… {n}", flush=True)

            # Insert edges in chunks
            upsert_edges(cur, edges, args.chunk)

            # Small sample
            report_dir = f"reports/upload_{args.upload_id}"
            sample = [(g, f"go-bp-{k.replace(':','_').lower()}") for k,sy in list(go_sets.items())[:2] for g in list(sy)[:3]]
            write_sample(report_dir, sample)

    print(f"[go-bp] DONE: terms={len(go_sets)}, edges={len(edges)}", flush=True)

if __name__ == "__main__":
    main()
