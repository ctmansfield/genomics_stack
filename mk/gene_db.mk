# --- Gene DB helpers (non-invasive include) -----------------------------------
.PHONY: db-refresh db-verify gene-card gene-search

# Refresh rollups + summary + (optional) search MV
db-refresh:
	./scripts/refresh_rollups.sh && \
	./scripts/refresh_summary.sh && \
	./scripts/refresh_gene_search.sh

# Run all verifiers we added
db-verify:
	./scripts/verify_edges.sh && \
	./scripts/verify_compact_summary.sh && \
	./scripts/verify_pathways.sh

# Pretty JSON gene card
# usage: make gene-card g=TP53
gene-card:
	@[ -n "$(g)" ] || (echo "usage: make gene-card g=GENE_SYMBOL" && exit 1)
	./scripts/gene_card.sh $(g)

# JSON search (prefix/full-text)
# usage: make gene-search q=brca n=10
gene-search:
	@[ -n "$(q)" ] || (echo "usage: make gene-search q=QUERY [n=N]" && exit 1)
	psql -XAt -c "SELECT public.search_genes_json('$(q)', $${n:-10});"

.PHONY: gene-card-file
gene-card-file:
	@[ -n "$(g)" ] || (echo "usage: make gene-card-file g=GENE [out=/tmp/x.json]"; exit 1)
	scripts/gene_card_to_file.sh "$(g)" "$${out:-/tmp/$(g)_card.json}"

.PHONY: db
db: db-refresh db-verify
