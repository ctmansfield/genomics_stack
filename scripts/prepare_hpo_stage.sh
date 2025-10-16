#!/usr/bin/env bash
# Build /tmp/hpo_gene.tsv from HPO exports without touching env vars.
# Output columns (TSV, no header):
# raw_gene_symbol  hpo_id  hpo_label  evidence  source

set +e  # respect user's no-strict-mode preference

OUT="/tmp/hpo_gene.tsv"

# 1) Resolve source file
CANDIDATES=()
if [ -n "${HPO_SOURCE:-}" ]; then
  CANDIDATES+=("$HPO_SOURCE")
fi
# Common defaults (do not require; just try them if HPO_SOURCE unset)
CANDIDATES+=(
  "/mnt/nas_storage/ref/hpo/phenotype_to_genes.txt"
  "/mnt/nas_storage/ref/hpo/phenotype_to_genes.tsv"
  "/mnt/nas_storage/ref/hpo/phenotype_to_genes.txt.gz"
  "/mnt/nas_storage/ref/hpo/genes_to_phenotypes.txt"
  "/mnt/nas_storage/ref/hpo/genes_to_phenotypes.tsv"
  "/mnt/nas_storage/ref/hpo/genes_to_phenotypes.txt.gz"
)

SRC=""
for f in "${CANDIDATES[@]}"; do
  [ -f "$f" ] && { SRC="$f"; break; }
done

if [ -z "$SRC" ]; then
  echo "[ERROR] Could not locate an HPO mapping file."
  echo "        Set HPO_SOURCE to your file path, e.g.:"
  echo "          export HPO_SOURCE=/mnt/nas_storage/ref/hpo/phenotype_to_genes.txt"
  echo "        Or place one of the common filenames in /mnt/nas_storage/ref/hpo/."
  exit 1
fi

# 2) Small helper to read first non-comment line (supports gz)
first_line() {
  local f="$1"
  if [[ "$f" == *.gz ]]; then
    zcat -f -- "$f" 2>/dev/null | grep -v '^#' | head -1
  else
    grep -v '^#' -- "$f" | head -1
  fi
}

HEADER="$(first_line "$SRC")"
if [ -z "$HEADER" ]; then
  echo "[ERROR] Unable to read $SRC (empty or only comments?)"
  exit 1
fi

# 3) Emit /tmp/hpo_gene.tsv based on detected schema
#    phenotype_to_genes.*: HPO-ID | HPO Name | Gene-ID | Gene Symbol
#    genes_to_phenotypes.*: Entrez Gene ID | Gene Symbol | HPO-ID | HPO Name | ...
produce_ptg() { # phenotype_to_genes
  if [[ "$SRC" == *.gz ]]; then
    zcat -f -- "$SRC" | awk -F'\t' 'BEGIN{skip=1}
      /^#/ {next}
      NR==1 && $1 ~ /HPO-ID/ {next}      # skip header row if present
      {print $4 "\t" $1 "\t" $2 "\t\tHPO"}' > "$OUT"
  else
    awk -F'\t' '
      /^#/ {next}
      NR==1 && $1 ~ /HPO-ID/ {next}
      {print $4 "\t" $1 "\t" $2 "\t\tHPO"}' "$SRC" > "$OUT"
  fi
}

produce_gtp() { # genes_to_phenotypes
  if [[ "$SRC" == *.gz ]]; then
    zcat -f -- "$SRC" | awk -F'\t' '
      /^#/ {next}
      NR==1 && $2 ~ /Gene Symbol/ {next}
      {print $2 "\t" $3 "\t" $4 "\t\tHPO"}' > "$OUT"
  else
    awk -F'\t' '
      /^#/ {next}
      NR==1 && $2 ~ /Gene Symbol/ {next}
      {print $2 "\t" $3 "\t" $4 "\t\tHPO"}' "$SRC" > "$OUT"
  fi
}

# 4) Decide which producer to use
if echo "$HEADER" | grep -q "HPO-ID"; then
  produce_ptg || { echo "[ERROR] reshape (PTG) failed"; exit 1; }
  echo "[OK] Wrote $OUT from phenotype_to_genes*"
elif echo "$HEADER" | grep -q "Gene Symbol"; then
  produce_gtp || { echo "[ERROR] reshape (GTP) failed"; exit 1; }
  echo "[OK] Wrote $OUT from genes_to_phenotypes*"
else
  # Heuristic fallback: try both, prefer producing non-empty output
  produce_ptg; ec1=$?
  if [ $ec1 -eq 0 ] && [ -s "$OUT" ]; then
    echo "[WARN] Unknown header; PTG heuristic used."
    exit 0
  fi
  produce_gtp; ec2=$?
  if [ $ec2 -eq 0 ] && [ -s "$OUT" ]; then
    echo "[WARN] Unknown header; GTP heuristic used."
    exit 0
  fi
  echo "[ERROR] Unrecognized HPO file schema in $SRC"
  exit 1
fi
