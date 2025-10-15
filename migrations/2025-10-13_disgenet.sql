BEGIN;
CREATE TABLE IF NOT EXISTS public.disgenet_diseases (
  disease_id   text PRIMARY KEY,        -- e.g., UMLS:C..., DOID:..., MeSH:D...
  name         text,
  source       text
);

CREATE TABLE IF NOT EXISTS public.disgenet_edges (
  gene_symbol  text NOT NULL,
  disease_id   text NOT NULL,
  score        numeric,                 -- DisGeNET score
  evidence     text,                    -- raw text/PMIDs/json per row
  source       text,                    -- curated/literature/ALL
  year         int,
  PRIMARY KEY (gene_symbol, disease_id, source)  -- de-dup by source
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS ix_disgenet_edges_gene ON public.disgenet_edges(gene_symbol);
CREATE INDEX IF NOT EXISTS ix_disgenet_edges_disease ON public.disgenet_edges(disease_id);
COMMIT;
