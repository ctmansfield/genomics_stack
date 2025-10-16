-- View: v_gene_search
-- Purpose: one row per canonical gene with aliases, top labels, counts, and a tsvector for fuzzy search.

CREATE OR REPLACE VIEW public.v_gene_search AS
WITH base AS (
  SELECT gc.gene_symbol
  FROM public.gene_catalog gc
),
aliases AS (
  -- distinct aliases grouped under the canonical symbol
  SELECT
    m.canonical AS gene_symbol,
    array_agg(DISTINCT m.alias ORDER BY m.alias)
      FILTER (WHERE m.alias IS NOT NULL AND m.alias <> m.canonical) AS aliases
  FROM public.mv_gene_symbol_canonical m
  GROUP BY m.canonical
),
h_counts AS (
  SELECT e.gene_symbol, e.hpo_id, COUNT(*) AS cnt
  FROM public.gene_to_hpo e
  GROUP BY e.gene_symbol, e.hpo_id
),
hpo_top AS (
  -- top HPO labels per gene by frequency
  SELECT
    hc.gene_symbol,
    array_agg(t.label ORDER BY hc.cnt DESC, t.label) AS hpo_labels_full
  FROM h_counts hc
  JOIN public.hpo_terms t ON t.hpo_id = hc.hpo_id
  GROUP BY hc.gene_symbol
),
summary AS (
  SELECT
    g.gene_symbol,
    COALESCE(g.n_go, 0)        AS n_go,
    COALESCE(g.n_bp, 0)        AS n_bp,
    COALESCE(g.n_mf, 0)        AS n_mf,
    COALESCE(g.n_cc, 0)        AS n_cc,
    COALESCE(g.n_pathways, 0)  AS n_pathways,
    COALESCE(g.n_pubmed, 0)    AS n_pubmed,
    COALESCE(g.n_drugs, 0)     AS n_drugs,
    COALESCE(g.n_hpo, 0)       AS n_hpo,
    COALESCE(g.n_total, 0)     AS n_total
  FROM public.v_gene_summary g
)
SELECT
  b.gene_symbol,
  COALESCE(a.aliases, '{}')                                   AS aliases,
  COALESCE(h.hpo_labels_full[1:5], '{}')                      AS hpo_labels,   -- top 5 HPO labels
  s.n_total, s.n_go, s.n_bp, s.n_mf, s.n_cc, s.n_pathways, s.n_pubmed, s.n_drugs, s.n_hpo,
  -- human-friendly concatenation for preview
  (
    b.gene_symbol || ' '
    || array_to_string(COALESCE(a.aliases,'{}'), ' ') || ' '
    || array_to_string(COALESCE(h.hpo_labels_full[1:5],'{}'), ' ')
  )                                                           AS search_text,
  -- search vector using simple parser for gene-like tokens
  to_tsvector('simple',
    b.gene_symbol || ' '
    || array_to_string(COALESCE(a.aliases,'{}'), ' ') || ' '
    || array_to_string(COALESCE(h.hpo_labels_full[1:5],'{}'), ' ')
  )                                                           AS search_vector
FROM base b
LEFT JOIN aliases a   ON a.gene_symbol = b.gene_symbol
LEFT JOIN hpo_top h   ON h.gene_symbol = b.gene_symbol
LEFT JOIN summary s   ON s.gene_symbol = b.gene_symbol;
