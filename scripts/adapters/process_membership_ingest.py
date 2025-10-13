#!/usr/bin/env python3
import os, re, csv, argparse, itertools
from typing import Optional, List, Tuple, Dict, Any
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
CREATE INDEX IF NOT EXISTS ix_bio_processes_slug        ON public.bio_processes(slug);
CREATE INDEX IF NOT EXISTS ix_gene_to_process_process   ON public.gene_to_process(process_id);
CREATE INDEX IF NOT EXISTS ix_gene_to_process_gene      ON public.gene_to_process(gene_symbol);
"""

def slugify(label: str) -> str:
    s = re.sub(r'[^A-Za-z0-9]+','-',label.strip()).strip('-').lower()
    return re.sub(r'-{2,}','-',s)[:200]

def parse_gmt(path: str) -> List[Tuple[str, Optional[str], List[str]]]:
    out = []
    with open(path, 'r') as f:
        for line in f:
            if not line.strip() or line.startswith('#'):
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 3:
                continue
            name, desc, *genes = parts
            label = name.replace('REACTOME_','').replace('_',' ').title()
            url = desc if desc.startswith('http') else None
            genes = [g.strip() for g in genes if g.strip()]
            out.append((label, url, genes))
    return out

def chunked(it, n):
    it = iter(it)
    while True:
        ch = list(itertools.islice(it, n))
        if not ch: break
        yield ch

def canonicalize(cur, sym: str) -> str:
    try:
        cur.execute("SELECT public.canonical_gene_symbol(%s)", (sym,))
        r = cur.fetchone()
        if r and r[0]: return r[0]
    except Exception:
        pass
    return sym

def get_columns(cur, table: str) -> Dict[str, str]:
    cur.execute("""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema='public' AND table_name=%s
    """, (table,))
    return {name: dtype for name, dtype in cur.fetchall()}

def detect_schema(cur) -> Dict[str, Any]:
    bio = get_columns(cur, "bio_processes")
    g2p = get_columns(cur, "gene_to_process")
    # Mode A: text ids
    if bio.get("process_id") == "text" and g2p.get("process_id") == "text":
        return {"mode":"text", "bio_pk":"process_id", "g2p_fk_type":"text"}
    # Mode B: numeric ids (id PK; g2p FK bigint/int)
    if ("id" in bio and bio["id"] in ("bigint","integer")) and g2p.get("process_id") in ("bigint","integer"):
        return {"mode":"numeric", "bio_id_col":"id", "g2p_fk_type":g2p["process_id"]}
    # Fallback: assume numeric if g2p FK is numeric
    if g2p.get("process_id") in ("bigint","integer"):
        return {"mode":"numeric", "bio_id_col":"id", "g2p_fk_type":g2p["process_id"]}
    # else assume text
    return {"mode":"text", "bio_pk":"process_id", "g2p_fk_type":"text"}

def ensure_process_numeric(cur, slug: str, label: str) -> int:
    # Upsert by slug; get id
    cur.execute("""
        INSERT INTO public.bio_processes (slug, label)
        VALUES (%s, %s)
        ON CONFLICT (slug) DO UPDATE SET label=EXCLUDED.label
        RETURNING process_id
    """, (slug, label))
    return cur.fetchone()[0]

def ensure_process_text(cur, slug: str, label: str):
    cur.execute("""
        INSERT INTO public.bio_processes (process_id, slug, label)
        VALUES (%s, %s, %s)
        ON CONFLICT (process_id) DO UPDATE SET slug=EXCLUDED.slug, label=EXCLUDED.label
    """, (slug, slug, label))

def upsert_processes(cur, sets, system_tag: Optional[str], schema: Dict[str,Any]) -> Dict[str, Any]:
    idmap = {}  # slug -> numeric id (only in numeric mode)
    if schema["mode"] == "numeric":
        for (label, url, genes) in sets:
            slug = slugify(label)
            pid = ensure_process_numeric(cur, slug, label)
            idmap[slug] = pid
        if system_tag:
            cur.executemany(
                "INSERT INTO public.process_to_system (process_id, system_tag, weight) VALUES (%s,%s,%s) "
                "ON CONFLICT (process_id, system_tag) DO NOTHING",
                [(idmap[slugify(label)], system_tag, 1.0) for (label, _, _) in sets]
            )
    else:
        payload = [(slugify(label), slugify(label), label) for (label, _, _) in sets]
        cur.executemany(
            "INSERT INTO public.bio_processes (process_id, slug, label) VALUES (%s,%s,%s) "
            "ON CONFLICT (process_id) DO UPDATE SET slug=EXCLUDED.slug, label=EXCLUDED.label",
            payload
        )
        if system_tag:
            cur.executemany(
                "INSERT INTO public.process_to_system (process_id, system_tag, weight) VALUES (%s,%s,%s) "
                "ON CONFLICT (process_id, system_tag) DO NOTHING",
                [(slugify(label), system_tag, 1.0) for (label, _, _) in sets]
            )
    return idmap

def insert_edges(cur, edges, weight: float, chunk_size: int, schema: Dict[str,Any]):
    for ch in chunked(edges, chunk_size):
        if schema["mode"] == "numeric":
            cur.executemany(
                "INSERT INTO public.gene_to_process (gene_symbol, process_id, role, sign, weight) "
                "VALUES (%s,%s,'member',1,%s) "
                "ON CONFLICT (gene_symbol, process_id) DO NOTHING",
                [(g, int(p), weight) for (g, p) in ch]
            )
        else:
            cur.executemany(
                "INSERT INTO public.gene_to_process (gene_symbol, process_id, role, sign, weight) "
                "VALUES (%s,%s,'member',1,%s) "
                "ON CONFLICT (gene_symbol, process_id) DO NOTHING",
                [(g, p, weight) for (g, p) in ch]
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

    pgurl = os.environ.get("PGURL")
    conn = psycopg.connect(pgurl) if pgurl else psycopg.connect("")

    edges = []
    processes = []  # (pid/slug, label)

    with conn:
        # Best-effort DDL
        try:
            with conn.cursor() as cur:
                cur.execute(DDL)
        except Exception as e:
            print(f"[process] DDL skipped ({e.__class__.__name__}: {e})", flush=True)

        with conn.cursor() as cur:
            schema = detect_schema(cur)
            print(f"[process] using schema mode: {schema['mode']}", flush=True)

            # Upsert processes, collect id map if numeric
            idmap = upsert_processes(cur, sets, args.system_tag, schema)

            # Prepare edges
            added = 0
            for (label, url, genes) in sets:
                slug = slugify(label)
                pid = idmap[slug] if schema["mode"] == "numeric" else slug
                for g in genes:
                    edges.append((canonicalize(cur, g), pid))
                    added += 1
                    if added % 100000 == 0:
                        print(f"[process] queued {added} edges…", flush=True)

        # Insert edges
        with conn.cursor() as cur:
            if edges:
                insert_edges(cur, edges, args.weight, args.chunk, schema)

    os.makedirs(f"reports/upload_{args.upload_id}", exist_ok=True)
    sample = f"reports/upload_{args.upload_id}/process_memberships_sample.csv"
    with open(sample, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["process_key","label","gene_symbol","system_tag","weight"])
        # label map for sample
        lab = {}
        for (label, url, genes) in sets:
            k = slugify(label)
            lab[k] = label
        for (g, pid) in edges[:200]:
            key = str(pid)
            # try reverse map via slug if numeric
            lbl = None
            if key in lab:
                lbl = lab[key]
            else:
                # best effort: recover slug from idmap
                lbl = None
            w.writerow([key, lbl if lbl else key, g, args.system_tag, args.weight])
    print(f"[process] wrote sample: {sample}", flush=True)
    print(f"[process] DONE: processes={len(sets)}, edges={len(edges)}", flush=True)

if __name__ == "__main__":
    main()
