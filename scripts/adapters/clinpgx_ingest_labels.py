#!/usr/bin/env python3
"""
ClinPGx — PharmGKB drug label adapter (link-only, idempotent).

Env:
  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
  PHARMGKB_LABELS=/mnt/.../drugLabels.tsv
  PHARMGKB_LICENSE="CC BY-SA 4.0"   (optional; if knowledge_sources exists)
  PHARMGKB_VERSION="YYYY-MM"        (optional; if knowledge_sources exists)
  CLINPGX_SKIP_KS=1                 (optional; skip touching knowledge_sources)
  CLINPGX_SKIP_EVIDENCE=1           (optional; skip biblio/evidence linking)

Usage:
  source .venv_gs2/bin/activate
  export PGHOST=192.168.1.225 PGPORT=5432 PGDATABASE=genome_db PGUSER=genouser PGPASSWORD=...
  export PHARMGKB_LABELS=/mnt/nas_storage/ref/pharmgkb/drugLabels.tsv
  python scripts/adapters/clinpgx_ingest_labels.py [--dry-run]
"""
from __future__ import annotations

import argparse
import csv
import logging
import os
import re
import sys
from typing import Dict, Iterable, List, Optional

import psycopg

logging.basicConfig(level=logging.INFO, format="[clinpgx] %(message)s")


# -------------------- DB helpers --------------------
def _dsn() -> str:
    host = os.getenv("PGHOST", "192.168.1.225")
    port = os.getenv("PGPORT", "5432")  # host Postgres
    db = os.getenv("PGDATABASE", "genomics")
    user = os.getenv("PGUSER", "genouser")
    pwd = os.getenv("PGPASSWORD", "")
    return f"host={host} port={port} dbname={db} user={user} password={pwd}"


def _labels_path() -> str:
    p = os.getenv("PHARMGKB_LABELS")
    if not p:
        print("Missing PHARMGKB_LABELS", file=sys.stderr)
        sys.exit(2)
    if not os.path.exists(p):
        print(f"Not found: {p}", file=sys.stderr)
        sys.exit(2)
    return p


def _table_exists(conn: psycopg.Connection, schema: str, name: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT 1 FROM information_schema.tables
            WHERE table_schema=%s AND table_name=%s
            """,
            (schema, name),
        )
        return cur.fetchone() is not None


def _table_columns(conn: psycopg.Connection, schema: str, name: str) -> List[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema=%s AND table_name=%s
            """,
            (schema, name),
        )
        return [r[0] for r in cur.fetchall()]


def _notnull_nodflt_cols(conn: psycopg.Connection, schema: str, name: str) -> List[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema=%s AND table_name=%s
              AND is_nullable='NO' AND (column_default IS NULL OR column_default='')
            """,
            (schema, name),
        )
        return [r[0] for r in cur.fetchall()]


def _pk_column(conn: psycopg.Connection, schema: str, table: str) -> Optional[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = %s
              AND tc.table_name   = %s
            ORDER BY kcu.ordinal_position
            """,
            (schema, table),
        )
        row = cur.fetchone()
        return row[0] if row else None


# -------------------- knowledge_sources (optional; isolated via manual SAVEPOINT) --------------------
def _ensure_knowledge_source(conn: psycopg.Connection) -> Optional[int]:
    """Best-effort upsert into knowledge_sources; skips on any schema mismatch."""
    if os.getenv("CLINPGX_SKIP_KS", "") == "1":
        logging.info("knowledge_sources skipped via CLINPGX_SKIP_KS=1")
        return None
    try:
        if not _table_exists(conn, "public", "knowledge_sources"):
            logging.info("knowledge_sources table not found; skipping source row")
            return None

        cols = set(_table_columns(conn, "public", "knowledge_sources"))
        req = {"name"}
        opt = {"license", "version"}
        idcands = ("knowledge_source_id", "id", "source_id")

        if "name" not in cols:
            logging.info("knowledge_sources lacks 'name'; skipping")
            return None

        id_col = next((c for c in idcands if c in cols), None)
        if not id_col:
            logging.info(f"knowledge_sources: no id column among {idcands}; skipping")
            return None

        # skip if there are additional NOT NULL no-default cols (e.g., 'kind')
        nnnd = set(_notnull_nodflt_cols(conn, "public", "knowledge_sources"))
        allowed = req | opt | set(idcands)
        unexpected = [c for c in nnnd if c not in allowed]
        if unexpected:
            logging.info(f"knowledge_sources has extra NOT NULL columns {unexpected}; skipping upsert")
            return None

        have_license = "license" in cols
        have_version = "version" in cols
        name = "PharmGKB"
        lic = os.getenv("PHARMGKB_LICENSE", None) if have_license else None
        ver = os.getenv("PHARMGKB_VERSION", None) if have_version else None

        with conn.cursor() as cur:
            cur.execute("SAVEPOINT ks")
            try:
                cur.execute(
                    f"SELECT {id_col} FROM public.knowledge_sources WHERE lower(name)=lower(%s) LIMIT 1",
                    (name,),
                )
                row = cur.fetchone()
                if row:
                    ks_id = row[0]
                    if have_license or have_version:
                        sql, params = "UPDATE public.knowledge_sources SET ", []
                        if have_license:
                            sql += "license=%s"
                            params.append(lic)
                        if have_version:
                            if params:
                                sql += ", "
                            sql += "version=%s"
                            params.append(ver)
                        sql += f" WHERE {id_col}=%s"
                        params.append(ks_id)
                        cur.execute(sql, tuple(params))
                    cur.execute("RELEASE SAVEPOINT ks")
                    return ks_id

                # insert
                if have_license or have_version:
                    cols_l = ["name"] + (["license"] if have_license else []) + (["version"] if have_version else [])
                    vals_l = ["%s"] + (["%s"] if have_license else []) + (["%s"] if have_version else [])
                    cur.execute(
                        f"INSERT INTO public.knowledge_sources({', '.join(cols_l)}) "
                        f"VALUES ({', '.join(vals_l)}) RETURNING {id_col}",
                        tuple([name] + ([lic] if have_license else []) + ([ver] if have_version else [])),
                    )
                else:
                    cur.execute(
                        f"INSERT INTO public.knowledge_sources(name) VALUES (%s) RETURNING {id_col}",
                        (name,),
                    )
                ks_id = cur.fetchone()[0]
                cur.execute("RELEASE SAVEPOINT ks")
                return ks_id
            except Exception as e:
                cur.execute("ROLLBACK TO SAVEPOINT ks")
                logging.info(f"knowledge_sources upsert skipped: {e}")
                return None
    except Exception as e:
        logging.info(f"knowledge_sources upsert skipped: {e}")
        return None


# -------------------- Evidence config discovery --------------------
def _discover_evidence_config(conn: psycopg.Connection) -> Optional[Dict[str, str]]:
    """Return mapping of column names if evidence linking is feasible; else None."""
    if os.getenv("CLINPGX_SKIP_EVIDENCE", "") == "1":
        logging.info("evidence linking skipped via CLINPGX_SKIP_EVIDENCE=1")
        return None
    if not (
        _table_exists(conn, "public", "biblio_refs")
        and _table_exists(conn, "public", "evidence_items")
        and _table_exists(conn, "public", "evidence_pgx_drug_labels")
    ):
        return None

    b_cols = set(_table_columns(conn, "public", "biblio_refs"))
    e_cols = set(_table_columns(conn, "public", "evidence_items"))
    br_cols = set(_table_columns(conn, "public", "evidence_pgx_drug_labels"))

    if "url" not in b_cols:
        return None

    b_pk = _pk_column(conn, "public", "biblio_refs")
    e_pk = _pk_column(conn, "public", "evidence_items")
    if not b_pk or not e_pk:
        return None

    # evidence_items FK to biblio_refs
    e_biblio_fk = None
    for cand in ("biblio_ref_id", "biblio_id", "ref_id", "biblio"):
        if cand in e_cols:
            e_biblio_fk = cand
            break
    if not e_biblio_fk:
        return None

    e_source = "source" if "source" in e_cols else ""

    # bridge fks
    br_label_fk = None
    for cand in ("row_id", "pgx_drug_label_id", "label_row_id", "label_id"):
        if cand in br_cols:
            br_label_fk = cand
            break
    if not br_label_fk:
        return None

    br_evi_fk = None
    for cand in ("evidence_id", "evidence_item_id", e_pk):
        if cand in br_cols:
            br_evi_fk = cand
            break
    if not br_evi_fk:
        return None

    return {
        "b_pk": b_pk,
        "b_url": "url",
        "e_pk": e_pk,
        "e_biblio_fk": e_biblio_fk,
        "e_source": e_source,
        "br_label_fk": br_label_fk,
        "br_evi_fk": br_evi_fk,
    }


# -------------------- TSV reader (prefers TAB; accepts CSV; last-resort space split) --------------------
def _dict_rows(path: str) -> Iterable[Dict[str, str]]:
    """
    Yield dict rows with lowercase keys.
    Prefers TAB-delimited. Also accepts CSV. As a last resort, splits on 2+ spaces.
    """
    with open(path, "r", encoding="utf-8") as fh:
        buf = fh.read()
    lines = buf.splitlines()
    if not lines:
        return

    # If header has tabs, parse as TSV
    if "\t" in lines[0]:
        reader = csv.DictReader(lines, delimiter="\t")
        for r in reader:
            yield {(k or "").strip().lower(): (v.strip() if isinstance(v, str) else v) for k, v in r.items()}
        return

    # Try CSV
    try:
        dialect = csv.Sniffer().sniff(buf, delimiters=",;")
        reader = csv.DictReader(lines, dialect=dialect)
        for r in reader:
            yield {(k or "").strip().lower(): (v.strip() if isinstance(v, str) else v) for k, v in r.items()}
        return
    except Exception:
        pass

    # Fallback: header + rows split by >=2 spaces (not ideal for values with spaces)
    header = re.split(r"\s{2,}", lines[0].strip())
    keys = [h.strip().lower() for h in header]
    for ln in lines[1:]:
        if not ln.strip():
            continue
        parts = re.split(r"\s{2,}", ln.strip())
        if len(parts) < len(keys):
            parts += [""] * (len(keys) - len(parts))
        yield {keys[i]: parts[i].strip() for i in range(min(len(keys), len(parts)))}


def _pick(d: Dict[str, str], *candidates: str) -> Optional[str]:
    for k in candidates:
        if k in d and d[k]:
            return d[k]
    return None


# -------------------- main ingest --------------------
def main(dry_run: bool):
    labels = _labels_path()
    with psycopg.connect(_dsn()) as conn, conn.cursor() as cur:
        conn.execute("SET search_path TO public, genomics")

        _ensure_knowledge_source(conn)  # safe / best-effort

        n_rows = 0
        n_drugs_ins = n_drugs_upd = 0
        n_labels_ins = n_labels_upd = 0
        n_evidence = 0

        evidence_cfg = _discover_evidence_config(conn)

        for row in _dict_rows(labels):
            n_rows += 1

            drug_name = _pick(row, "drug name", "drug", "name")
            if not drug_name:
                continue

            biomarker = _pick(row, "biomarker", "gene", "biomarker/gene") or None
            agency = _pick(row, "label type/agency", "agency", "source", "regulatory body") or None
            label_flag = _pick(row, "pgx level", "pharmacogenomic level", "pgx level (fda)", "label flag", "label class") or None
            url = _pick(row, "url", "web page url", "link") or None

            # upsert drug_catalog (case-insensitive on preferred_name)
            cur.execute(
                """
                SELECT drug_id, preferred_name
                FROM public.drug_catalog
                WHERE lower(preferred_name)=lower(%s)
                LIMIT 1
                """,
                (drug_name,),
            )
            hit = cur.fetchone()
            if hit:
                drug_id = hit[0]
                if hit[1] != drug_name and not dry_run:
                    cur.execute(
                        """UPDATE public.drug_catalog SET preferred_name=%s WHERE drug_id=%s""",
                        (drug_name, drug_id),
                    )
                    n_drugs_upd += 1
            else:
                if dry_run:
                    drug_id = -1
                    n_drugs_ins += 1
                else:
                    cur.execute(
                        """INSERT INTO public.drug_catalog(preferred_name) VALUES (%s) RETURNING drug_id""",
                        (drug_name,),
                    )
                    drug_id = cur.fetchone()[0]
                    n_drugs_ins += 1

            # Upsert pgx_drug_labels by (agency, drug_id, url, biomarker) NULL-safe
            cur.execute(
                """
                SELECT row_id, label_flag FROM public.pgx_drug_labels
                WHERE agency IS NOT DISTINCT FROM %s
                  AND drug_id = %s
                  AND url IS NOT DISTINCT FROM %s
                  AND biomarker IS NOT DISTINCT FROM %s
                """,
                (agency, drug_id, url, biomarker),
            )
            hit = cur.fetchone()
            if hit:
                row_id, old_flag = hit
                if old_flag != label_flag and not dry_run:
                    cur.execute(
                        """UPDATE public.pgx_drug_labels
                           SET label_flag=%s, biomarker=%s
                           WHERE row_id=%s""",
                        (label_flag, biomarker, row_id),
                    )
                n_labels_upd += 1
            else:
                if not dry_run:
                    cur.execute(
                        """INSERT INTO public.pgx_drug_labels(agency, drug_id, biomarker, label_flag, url)
                           VALUES (%s,%s,%s,%s,%s) RETURNING row_id""",
                        (agency, drug_id, biomarker, label_flag, url),
                    )
                    row_id = cur.fetchone()[0]
                else:
                    row_id = -1
                n_labels_ins += 1

                # evidence (BEST-EFFORT; skip silently if schema doesn't fit)
                if not dry_run and url and evidence_cfg:
                    try:
                        b_pk = evidence_cfg["b_pk"]
                        b_url = evidence_cfg["b_url"]
                        e_pk = evidence_cfg["e_pk"]
                        e_biblio_fk = evidence_cfg["e_biblio_fk"]
                        e_source = evidence_cfg["e_source"]
                        br_label_fk = evidence_cfg["br_label_fk"]
                        br_evi_fk = evidence_cfg["br_evi_fk"]

                        # upsert/select biblio_refs by url
                        cur.execute(f"""SELECT {b_pk} FROM public.biblio_refs WHERE {b_url}=%s LIMIT 1""", (url,))
                        b = cur.fetchone()
                        if b:
                            b_id = b[0]
                        else:
                            cur.execute(
                                f"""INSERT INTO public.biblio_refs({b_url}) VALUES (%s) RETURNING {b_pk}""",
                                (url,),
                            )
                            b_id = cur.fetchone()[0]

                        # insert evidence_items
                        if e_source:
                            cur.execute(
                                f"""INSERT INTO public.evidence_items({e_biblio_fk}, {e_source})
                                    VALUES (%s,%s) RETURNING {e_pk}""",
                                (b_id, "PharmGKB"),
                            )
                        else:
                            cur.execute(
                                f"""INSERT INTO public.evidence_items({e_biblio_fk})
                                    VALUES (%s) RETURNING {e_pk}""",
                                (b_id,),
                            )
                        e_id = cur.fetchone()[0]

                        # bridge insert
                        try:
                            cur.execute(
                                f"""INSERT INTO public.evidence_pgx_drug_labels({br_label_fk}, {br_evi_fk})
                                    VALUES (%s,%s) ON CONFLICT DO NOTHING""",
                                (row_id, e_id),
                            )
                        except Exception:
                            cur.execute(
                                f"""INSERT INTO public.evidence_pgx_drug_labels({br_label_fk}, {br_evi_fk})
                                    VALUES (%s,%s)""",
                                (row_id, e_id),
                            )
                        n_evidence += 1
                    except Exception as e:
                        logging.info(f"evidence link skipped for url={url!r}: {e}")

        if dry_run:
            conn.rollback()
        else:
            conn.commit()

        logging.info(
            f"rows_seen={n_rows} drugs_ins={n_drugs_ins} drugs_upd={n_drugs_upd} "
            f"labels_ins={n_labels_ins} labels_upd={n_labels_upd} evidence_added={n_evidence}"
        )
        print(
            {
                "rows_seen": n_rows,
                "drugs_inserted": n_drugs_ins,
                "drugs_updated": n_drugs_upd,
                "labels_inserted": n_labels_ins,
                "labels_updated": n_labels_upd,
                "evidence_added": n_evidence,
            }
        )


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="ClinPGx: ingest PharmGKB drug labels (link-only)")
    ap.add_argument("--dry-run", action="store_true", help="Parse and report without writing to DB")
    args = ap.parse_args()
    main(args.dry_run)
