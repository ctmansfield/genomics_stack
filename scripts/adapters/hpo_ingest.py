#!/usr/bin/env python3
"""
HPO genes→phenotypes ingest.

- Tries to download the file if --source isn't provided
- Parses flexible headers (upper/lower/mixed, CRLF ok)
- Best-effort DDL (skips if not owner)
- Inserts/updates terms and edges
- Writes a small sample CSV in reports/upload_<id>/

Usage:
  PYTHONUNBUFFERED=1 python3 scripts/adapters/hpo_ingest.py \
    --upload-id 2 \
    --version "HPO genes_to_phenotype v2025-09-01" \
    [--source /path/to/ALL_SOURCES_ALL_FREQUENCIES_genes_to_phenotype.txt] \
    [--chunk 5000] [--progress-every 50000]
"""

import argparse, csv, os, sys, time, gzip, io, re, urllib.request
from pathlib import Path
import psycopg

# Optional helpers (present in repo). If missing, inline fallbacks.
try:
    from adapters._ingest_utils import ensure_dir, write_csv_sample, chunked
except Exception:
    def ensure_dir(p: Path):
        p.mkdir(parents=True, exist_ok=True)
    def write_csv_sample(path: Path, header=None, rows=None, limit=50):
        ensure_dir(path.parent); 
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if header: w.writerow(header)
            for i, r in enumerate(rows or []):
                if i >= limit: break
                w.writerow(r)
    def chunked(iterable, n=5000):
        buf=[]
        for x in iterable:
            buf.append(x)
            if len(buf)>=n:
                yield buf; buf=[]
        if buf: yield buf

DDL_TERMS = """
CREATE TABLE IF NOT EXISTS public.hpo_terms(
  hp_id      text PRIMARY KEY,
  label      text,
  updated_at timestamptz DEFAULT now()
);
"""

DDL_EDGES = """
CREATE TABLE IF NOT EXISTS public.gene_to_hpo(
  id          bigserial PRIMARY KEY,
  gene_symbol text NOT NULL REFERENCES public.gene_catalog(gene_symbol),
  hp_id       text NOT NULL REFERENCES public.hpo_terms(hp_id) ON DELETE CASCADE,
  evidence    text,
  source      text DEFAULT 'HPO',
  updated_at  timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_gene_to_hpo_gene ON public.gene_to_hpo(gene_symbol);
CREATE INDEX IF NOT EXISTS ix_gene_to_hpo_hp   ON public.gene_to_hpo(hp_id);
"""

MIRRORS = [
  # release tag example (fastest if you know the tag)
  "https://github.com/obophenotype/human-phenotype-ontology/releases/download/v2025-09-01/genes_to_phenotype.txt",
  # historical “ALL_SOURCES_all_FREQUENCIES_...” names seen in mirrors
  "https://storage.googleapis.com/hpo-annotation/annotation/ALL_SOURCES_all_FREQUENCIES_genes_to_phenotype.txt",
  "https://data.monarchinitiative.org/hpo/annotation/ALL_SOURCES_all_FREQUENCIES_genes_to_phenotype.txt",
  "https://raw.githubusercontent.com/obophenotype/hpo-annotation-files/master/annotation/ALL_SOURCES_all_FREQUENCIES_genes_to_phenotype.txt",
]

def open_text(path: Path):
    data = path.read_bytes()
    # normalize CRLF -> LF
    data = data.replace(b"\r\n", b"\n")
    return io.TextIOWrapper(io.BytesIO(data), encoding="utf-8", errors="replace")

def smart_download(dest: Path) -> Path:
    err_last = None
    for url in MIRRORS:
        try:
            print(f"[hpo] trying {url}", flush=True)
            with urllib.request.urlopen(url, timeout=60) as r:
                data = r.read()
            ensure_dir(dest.parent)
            dest.write_bytes(data)
            print(f"[hpo] downloaded -> {dest} ({len(data):,} bytes)", flush=True)
            return dest
        except Exception as e:
            err_last = e
            print(f"[hpo] WARN: fetch failed for {url} ({e})", flush=True)
    raise RuntimeError(f"could not fetch HPO genes_to_phenotype from mirrors: {err_last}")

def parse_rows(fh):
    """Yield tuples: (gene_symbol, hp_id, label, evidence) from flexible headers."""
    header = fh.readline()
    while header.startswith("#"):
        header = fh.readline()
    if not header:
        return
    cols = [c.strip() for c in header.rstrip("\n").split("\t")]
    idx = {c.lower(): i for i, c in enumerate(cols)}

    def col(*names):
        for n in names:
            i = idx.get(n.lower())
            if i is not None:
                return i
        return None

    i_sym = col("gene_symbol","gene-symbol","entrez-gene-symbol","gene symbol")
    i_hp  = col("hpo_id","hpo-id","hpo id")
    i_lab = col("hpo_name","hpo-term-name","hpo term name","hpo-term")
    i_evi = col("evidence","frequency","biocuration")

    if i_sym is None or i_hp is None:
        raise RuntimeError(f"Required columns missing. Got: {cols}")

    for line in fh:
        if not line or line.startswith("#"): 
            continue
        parts = line.rstrip("\n").split("\t")
        g = parts[i_sym] if i_sym < len(parts) else ""
        p = parts[i_hp]  if i_hp  < len(parts) else ""
        l = parts[i_lab] if i_lab is not None and i_lab < len(parts) else ""
        e = parts[i_evi] if i_evi is not None and i_evi < len(parts) else ""
        if g and p:
            yield (g, p, l, e)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", help="Path to genes_to_phenotype.txt (optional: will download if missing)")
    ap.add_argument("--upload-id", type=int, default=None)
    ap.add_argument("--version", default="HPO genes_to_phenotype")
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    print(f"[pgenv] PGHOST={os.getenv('PGHOST')} PGPORT={os.getenv('PGPORT')} PGUSER={os.getenv('PGUSER')} PGDATABASE={os.getenv('PGDATABASE')}", flush=True)

    src_path = Path(args.source) if args.source else None
    if not src_path:
        # default location
        src_path = Path("/mnt/nas_storage/ref/hpo/ALL_SOURCES_ALL_FREQUENCIES_genes_to_phenotype.txt")
        if not src_path.exists():
            src_path = smart_download(src_path)

    if not src_path.exists():
        raise SystemExit(f"[hpo] ERROR: source not found: {src_path}")

    # Read file & parse
    t0 = time.time()
    rows = list(parse_rows(open_text(src_path)))
    print(f"[hpo] parsed {len(rows):,} rows from {src_path.name}", flush=True)

    # Set up reporting dir
    outdir = Path(f"reports/upload_{args.upload_id or 0}")
    ensure_dir(outdir)
    write_csv_sample(outdir / "hpo_g2p_sample.csv",
                     header=["gene_symbol","hp_id","label","evidence"],
                     rows=rows)

    # DB work
    with psycopg.connect("") as conn:
        with conn:
            with conn.cursor() as cur:
                # best-effort DDL
                try:
                    cur.execute(DDL_TERMS)
                    cur.execute(DDL_EDGES)
                except Exception as e:
                    print(f"[hpo] DDL skipped ({e.__class__.__name__}: {e})", flush=True)

            # upsert terms first (distinct hp_id,label)
            seen_terms = {}
            for g, hp, lab, evi in rows:
                if hp not in seen_terms:
                    seen_terms[hp] = lab

            term_data = [(hp, (seen_terms[hp] or None)) for hp in seen_terms.keys()]

            with conn.cursor() as cur:
                cur.executemany("""
                    INSERT INTO public.hpo_terms(hp_id, label, updated_at)
                    VALUES (%s, %s, now())
                    ON CONFLICT (hp_id) DO UPDATE
                      SET label = COALESCE(EXCLUDED.label, public.hpo_terms.label),
                          updated_at = now()
                """, term_data)

            # edges (only genes that exist in gene_catalog)
            # we’ll insert ignoring dupes using NOT EXISTS so it works regardless of unique constraints present
            def edge_chunks():
                for chunk in chunked(rows, n=args.chunk):
                    # collapse in-python to reduce dup work
                    seen = set()
                    batch=[]
                    for g,hp,lab,evi in chunk:
                        key=(g,hp,(evi or None))
                        if key in seen: 
                            continue
                        seen.add(key)
                        batch.append(key)
                    yield batch

            total = 0
            printed = 0
            for batch in edge_chunks():
                with conn.cursor() as cur:
                    cur.executemany("""
                        WITH v(g,hp,evi) AS (VALUES (%s,%s,%s))
                        INSERT INTO public.gene_to_hpo(gene_symbol, hp_id, evidence, source, updated_at)
                        SELECT g, hp, evi, 'HPO', now()
                        FROM v
                        WHERE EXISTS (SELECT 1 FROM public.gene_catalog gc WHERE gc.gene_symbol = g)
                          AND EXISTS (SELECT 1 FROM public.hpo_terms t WHERE t.hp_id = hp)
                          AND NOT EXISTS (
                              SELECT 1 FROM public.gene_to_hpo e
                              WHERE e.gene_symbol = g
                                AND e.hp_id       = hp
                                AND COALESCE(e.evidence,'') = COALESCE(evi,'')
                          )
                    """, batch)
                total += len(batch)
                if args.progress_every and total - printed >= args.progress_every:
                    print(f"[hpo] ...processed {total:,} rows", flush=True)
                    printed = total

    dt = time.time() - t0
    print(f"[hpo] DONE: rows_in={len(rows):,} (unique terms={len(term_data):,}), elapsed={dt:.1f}s", flush=True)
    print(f"[hpo] wrote sample: {outdir/'hpo_g2p_sample.csv'}", flush=True)

if __name__ == "__main__":
    main()
