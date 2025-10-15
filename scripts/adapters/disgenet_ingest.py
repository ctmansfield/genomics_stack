#!/usr/bin/env python3
"""
DisGeNET TSV ingester

Usage:
  python3 scripts/adapters/disgenet_ingest.py /mnt/nas_storage/ref/disgenet/disgenet_edges.tsv

Input TSV columns (flexible; header-driven). Works with common DisGeNET exports:
  - geneSymbol, diseaseId, diseaseName, score, source, year, pmids
  - Accepts gzip (.gz) or plain .tsv

Behavior:
  - Canonicalizes gene symbols via public.canonical_gene_symbol(text)
  - Normalizes disease IDs to prefixed form: UMLS:C..., DOID:..., MESH:D..., else passes through
  - Upserts diseases (id, name, source) and edges (gene, disease, score, source, year, evidence/pmids)
  - De-dupes rows before upsert to avoid PK churn

Env knobs:
  - MIN_SCORE: float (optional) -> skip edges with score < MIN_SCORE
  - BATCH_SIZE: int (default 5000)
  - PG* env are read from your session (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)
"""
import os, sys, csv, gzip, io
from decimal import Decimal, InvalidOperation
import psycopg2
from psycopg2.extras import execute_values

def open_maybe_gzip(path):
    if path.endswith(".gz"):
        return io.TextIOWrapper(gzip.open(path, "rb"), encoding="utf-8", newline="")
    return open(path, "r", encoding="utf-8", newline="")

def norm_disease_id(raw: str) -> str:
    if not raw:
        return None
    s = raw.strip()
    # Common DisGeNET formats:
    # - UMLS CUI "C000000" (no prefix) -> prefix it
    # - Already prefixed (UMLS:, DOID:, MESH:) -> keep
    # - MeSH bare "D012345" -> MESH:D012345
    if ":" in s:
        return s
    if s.startswith("C") and s[1:].isdigit():
        return "UMLS:" + s
    if (s.startswith("D") and s[1:].isdigit()) or s.startswith("D") and s[1:].replace("0","").isdigit():
        return "MESH:" + s
    return s  # pass-through for orphan namespaces

def to_decimal(x):
    if x is None or x == "":
        return None
    try:
        return Decimal(x)
    except InvalidOperation:
        return None

def to_int(x):
    try:
        return int(x)
    except Exception:
        return None

def main():
    if len(sys.argv) != 2:
        print("Usage: disgenet_ingest.py /path/to/disgenet.tsv[.gz]", file=sys.stderr)
        sys.exit(1)

    tsv_path = sys.argv[1]
    if not os.path.exists(tsv_path):
        print(f"Input not found: {tsv_path}", file=sys.stderr)
        sys.exit(1)

    min_score = os.environ.get("MIN_SCORE")
    min_score = Decimal(min_score) if min_score else None
    batch_size = int(os.environ.get("BATCH_SIZE", "5000"))

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD"),
        dbname=os.environ.get("PGDATABASE", "postgres"),
    )
    conn.autocommit = False
    cur = conn.cursor()

    # Ensure tables exist (idempotent safety net)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS public.disgenet_diseases (
      disease_id   text PRIMARY KEY,
      name         text,
      source       text
    );
    CREATE TABLE IF NOT EXISTS public.disgenet_edges (
      gene_symbol  text NOT NULL,
      disease_id   text NOT NULL,
      score        numeric,
      evidence     text,
      source       text,
      year         int,
      PRIMARY KEY (gene_symbol, disease_id, source)
    );
    """)

    # Prepare canonicalization function check
    cur.execute("SELECT proname FROM pg_proc WHERE proname='canonical_gene_symbol';")
    has_canonical = cur.fetchone() is not None

    # Read TSV
    with open_maybe_gzip(tsv_path) as f:
        rdr = csv.DictReader(f, delimiter="\t")
        # Flexible column keys
        # Common options:
        #   geneSymbol | gene_symbol | symbol
        #   diseaseId | disease_id | diseaseIdentifier
        #   diseaseName | disease_name
        #   score | DGNscore
        #   source
        #   year
        #   pmids | pubmedIds | evidence
        def pick(d, keys, default=None):
            for k in keys:
                if k in d and d[k] != "":
                    return d[k]
            return default

        diseases_dedup = {}
        edges_dedup = {}

        for row in rdr:
            gene = pick(row, ["geneSymbol", "gene_symbol", "symbol"])
            dis_id_raw = pick(row, ["diseaseId", "disease_id", "diseaseIdentifier"])
            dis_name = pick(row, ["diseaseName", "disease_name"])
            score = to_decimal(pick(row, ["score", "DGNscore"]))
            source = pick(row, ["source"])
            year = to_int(pick(row, ["year"]))
            evidence = pick(row, ["pmids", "pubmedIds", "evidence"])

            if not gene or not dis_id_raw or not source:
                continue

            if min_score is not None and score is not None and score < min_score:
                continue

            dis_id = norm_disease_id(dis_id_raw)
            # canonicalize gene symbol
            if has_canonical:
                cur.execute("SELECT public.canonical_gene_symbol(%s);", (gene,))
                gene_canon = cur.fetchone()[0] or gene
            else:
                gene_canon = gene

            # de-dup last-wins per (gene,disease,source)
            edges_dedup[(gene_canon, dis_id, source)] = (gene_canon, dis_id, score, evidence, source, year)

            # prefer first non-empty disease name per id, keep latest source seen
            if dis_id not in diseases_dedup:
                diseases_dedup[dis_id] = (dis_id, dis_name, source)
            else:
                prev = diseases_dedup[dis_id]
                if (not prev[1]) and dis_name:
                    diseases_dedup[dis_id] = (dis_id, dis_name, source)
                else:
                    # keep existing name, but update source if new info present
                    diseases_dedup[dis_id] = (dis_id, prev[1], source or prev[2])

    # Upsert diseases
    if diseases_dedup:
        execute_values(cur, """
            INSERT INTO public.disgenet_diseases (disease_id, name, source)
            VALUES %s
            ON CONFLICT (disease_id) DO UPDATE
              SET name = COALESCE(EXCLUDED.name, public.disgenet_diseases.name),
                  source = COALESCE(EXCLUDED.source, public.disgenet_diseases.source)
        """, list(diseases_dedup.values()), page_size=batch_size)

    # Upsert edges
    edge_rows = list(edges_dedup.values())
    if edge_rows:
        execute_values(cur, """
            INSERT INTO public.disgenet_edges (gene_symbol, disease_id, score, evidence, source, year)
            VALUES %s
            ON CONFLICT (gene_symbol, disease_id, source) DO UPDATE
              SET score = COALESCE(EXCLUDED.score, public.disgenet_edges.score),
                  evidence = COALESCE(EXCLUDED.evidence, public.disgenet_edges.evidence),
                  year = COALESCE(EXCLUDED.year, public.disgenet_edges.year)
        """, edge_rows, page_size=batch_size)

    conn.commit()
    cur.close()
    conn.close()
    print(f"Loaded {len(edge_rows)} edges; {len(diseases_dedup)} diseases")
    return 0

if __name__ == "__main__":
    sys.exit(main())
