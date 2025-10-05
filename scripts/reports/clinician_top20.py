#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from typing import List, Dict, Tuple

import psycopg2


DEFAULT_SYSTEM_ORDER = [
    "Cardiovascular",
    "Metabolic",
    "Endocrine",
    "Immune",
    "Neuro",
    "Detox/Liver",
    "Nutrient Metabolism",
    "General",
    "Other",
]


@dataclass
class Row:
    src: str
    rsid: str
    symbol: str | None
    title: str
    zygosity: str | None
    impact: str | None
    score: str | None
    weight: str | None
    paired_with: str | None
    notes: str | None
    rank_score: float | None
    system_tag: str
    impact_blurb: str | None
    nutrition_note: str | None
    evidence_notes: str | None


def env(k: str, default: str | None = None) -> str | None:
    v = os.environ.get(k, default)
    return v


def fetch_candidates(dsn: str, upload_id: int, topn: int = 50) -> List[Row]:
    rows: List[Row] = []
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        # Detect presence of VEP join table to avoid errors on missing relation
        cur.execute(
            """
            SELECT EXISTS (
              SELECT 1 FROM information_schema.tables
              WHERE table_schema='anno' AND table_name='vep_joined'
            )
            """
        )
        has_vep = bool(cur.fetchone()[0])

        if has_vep:
            sql = f"""
            WITH
            risk AS (
              SELECT
                'risk' AS src,
                COALESCE(v.rsid,'-') AS rsid,
                g.symbol,
                r.short_title AS title,
                h.zygosity,
                NULL::text AS impact,
                r.weight::text AS weight,
                h.score::text  AS score,
                r.evidence_notes AS notes,
                h.score::numeric AS rank_score,
                COALESCE(r.system_tag,'General') AS system_tag,
                r.impact_blurb,
                r.nutrition_note,
                r.evidence_notes
              FROM public.risk_hits h
              JOIN public.risk_rules r ON r.rule_id = h.rule_id
              JOIN public.genes      g ON g.gene_id = r.gene_id
              LEFT JOIN public.variants v ON v.variant_id = r.variant_id
              WHERE h.upload_id = %s
            ),
            vep_pick AS (
              SELECT DISTINCT ON (COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol))
                     'vep' AS src,
                     COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, '-') AS rsid,
                     NULLIF(j.symbol,'') AS symbol,
                     j.consequence AS title,
                     NULL::text AS zygosity,
                     j.impact,
                     NULL::text AS weight,
                     NULL::text AS score,
                     NULLIF(j.clin_sig,'') AS notes,
                     (anno.vep_impact_rank(j.impact))*100
                       + CASE WHEN NULLIF(j.clin_sig,'') IS NOT NULL THEN 10 ELSE 0 END
                       + COALESCE( (1 - NULLIF(j.af,'-')::numeric), 0 )::numeric AS rank_score,
                     'General'::text AS system_tag,
                     NULL::text AS impact_blurb,
                     NULL::text AS nutrition_note,
                     NULL::text AS evidence_notes
              FROM anno.vep_joined j
              WHERE j.upload_id = %s
              ORDER BY COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol),
                       (anno.vep_impact_rank(j.impact)) DESC NULLS LAST,
                       NULLIF(j.clin_sig,'') DESC NULLS LAST
            ),
            unioned AS (
              SELECT * FROM risk
              UNION ALL
              SELECT * FROM vep_pick
            ),
            ranked AS (
              SELECT u.*, ROW_NUMBER() OVER (ORDER BY rank_score DESC NULLS LAST, symbol NULLS LAST, rsid) AS rn
              FROM unioned u
            )
            SELECT src, rsid, symbol, title, zygosity, impact, score, weight, notes, rank_score,
                   system_tag, impact_blurb, nutrition_note, evidence_notes,
                   NULL::text as paired_with
            FROM ranked
            WHERE rn <= %s
            """
            cur.execute(sql, (upload_id, upload_id, topn))
        else:
            sql = f"""
            WITH
            risk AS (
              SELECT
                'risk' AS src,
                COALESCE(v.rsid,'-') AS rsid,
                g.symbol,
                r.short_title AS title,
                h.zygosity,
                NULL::text AS impact,
                r.weight::text AS weight,
                h.score::text  AS score,
                r.evidence_notes AS notes,
                h.score::numeric AS rank_score,
                COALESCE(r.system_tag,'General') AS system_tag,
                r.impact_blurb,
                r.nutrition_note,
                r.evidence_notes
              FROM public.risk_hits h
              JOIN public.risk_rules r ON r.rule_id = h.rule_id
              JOIN public.genes      g ON g.gene_id = r.gene_id
              LEFT JOIN public.variants v ON v.variant_id = r.variant_id
              WHERE h.upload_id = %s
            ),
            ranked AS (
              SELECT rsk.*, ROW_NUMBER() OVER (ORDER BY rank_score DESC NULLS LAST, symbol NULLS LAST, rsid) AS rn
              FROM risk rsk
            )
            SELECT src, rsid, symbol, title, zygosity, impact, score, weight, notes, rank_score,
                   system_tag, impact_blurb, nutrition_note, evidence_notes,
                   NULL::text as paired_with
            FROM ranked
            WHERE rn <= %s
            """
            cur.execute(sql, (upload_id, topn))

        for r in cur.fetchall():
            rows.append(
                Row(
                    src=r[0], rsid=r[1] or '-', symbol=r[2], title=r[3] or '-', zygosity=r[4],
                    impact=r[5], score=r[6], weight=r[7], notes=r[8], rank_score=float(r[9]) if r[9] is not None else None,
                    system_tag=r[10] or 'General', impact_blurb=r[11], nutrition_note=r[12], evidence_notes=r[13],
                    paired_with=r[14],
                )
            )
    return rows


def enforce_system_coverage(rows: List[Row], max_rows: int = 20, system_order: List[str] | None = None) -> List[Row]:
    if not rows:
        return []
    order = system_order or DEFAULT_SYSTEM_ORDER
    # Rank by rank_score (desc), keeping original order as tiebreaker via enumerate
    ranked = sorted(list(enumerate(rows)), key=lambda x: (x[1].rank_score is None, -(x[1].rank_score or 0), x[0]))
    by_system: Dict[str, List[Tuple[int, Row]]] = {}
    for idx, row in ranked:
        by_system.setdefault(row.system_tag or 'General', []).append((idx, row))
    selection: List[Tuple[int, Row]] = []
    # First pass: at least one per present system in canonical order
    for sys_name in order:
        if sys_name in by_system and by_system[sys_name]:
            selection.append(by_system[sys_name][0])
    # Second pass: fill remaining by global rank
    picked = set(i for i, _ in selection)
    for idx, row in ranked:
        if len(selection) >= max_rows:
            break
        if idx not in picked:
            selection.append((idx, row))
            picked.add(idx)
    # Truncate if over
    selection = selection[:max_rows]
    # Restore a stable display order: by system canonical order first, then rank
    def sort_key(item: Tuple[int, Row]):
        _, r = item
        sys_idx = order.index(r.system_tag) if r.system_tag in order else len(order)
        return (sys_idx, -(r.rank_score or 0), r.symbol or 'ZZZ', r.rsid)
    selection.sort(key=sort_key)
    return [r for _, r in selection]


def render_html(rows: List[Row], title: str) -> str:
    def esc(s: str) -> str:
        return (
            (s or "-")
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
        )
    out = [
        f"<!doctype html><meta charset=utf-8><title>{esc(title)}</title>",
        "<style>body{font:14px sans-serif;margin:20px} h2{margin-top:28px} "+
        "table{border-collapse:collapse;width:100%} th,td{border:1px solid #ccc;padding:6px;} th{background:#f6f6f6;text-align:left}</style>",
        f"<h1>{esc(title)}</h1>",
    ]
    # Group by system
    by_sys: Dict[str, List[Row]] = {}
    for r in rows:
        by_sys.setdefault(r.system_tag or 'General', []).append(r)
    for sys_name in DEFAULT_SYSTEM_ORDER:
        if sys_name not in by_sys:
            continue
        out.append(f"<h2>{esc(sys_name)}</h2>")
        out.append("<table><thead><tr>" + "".join(
            f"<th>{h}</th>" for h in ["RSID","Gene","Title","Zygosity","Impact","Score","Weight","Explanation","Notes","Evidence"]
        ) + "</tr></thead><tbody>")
        for r in by_sys[sys_name]:
            out.append("<tr>" + "".join([
                f"<td>{esc(r.rsid)}</td>",
                f"<td>{esc(r.symbol or '-') }</td>",
                f"<td>{esc(r.title)}</td>",
                f"<td>{esc(r.zygosity or '-') }</td>",
                f"<td>{esc(r.impact or '-') }</td>",
                f"<td>{esc(r.score or '-') }</td>",
                f"<td>{esc(r.weight or '-') }</td>",
                f"<td>{esc(r.impact_blurb or '-') }</td>",
                f"<td>{esc(r.nutrition_note or '-') }</td>",
                f"<td>{esc(r.evidence_notes or '-') }</td>",
            ]) + "</tr>")
        out.append("</tbody></table>")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", type=int, required=True)
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--dsn", default=os.getenv("PG_DSN"))
    ap.add_argument("--out-html", required=True)
    args = ap.parse_args()

    if not args.dsn:
        print("PG_DSN not set; pass --dsn", file=sys.stderr)
        sys.exit(2)

    candidates = fetch_candidates(args.dsn, args.upload_id, topn=max(args.limit * 3, 60))
    selected = enforce_system_coverage(candidates, max_rows=args.limit, system_order=DEFAULT_SYSTEM_ORDER)

    html = render_html(selected, title=f"Clinician Top {args.limit} – Upload {args.upload_id}")
    os.makedirs(os.path.dirname(args.out_html) or ".", exist_ok=True)
    with open(args.out_html, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[ok] HTML: {args.out_html} (rows={len(selected)})")


if __name__ == "__main__":
    main()
