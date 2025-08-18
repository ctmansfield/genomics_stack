# shellcheck shell=bash
[ -f /root/.pg_env ] && . /root/.pg_env
#!/usr/bin/env bash
set -euo pipefail

# Ensure wkhtmltopdf + fonts (host install)
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
  echo "[install] Installing wkhtmltopdf + fonts (apt)…"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y wkhtmltopdf fontconfig fonts-dejavu-core || {
    echo "[install] apt install failed; please install wkhtmltopdf manually"; exit 2; }
fi

# Ensure out dir
OUT=/root/genomics-stack/risk_reports/out
mkdir -p "$OUT"

# Drop in a tiny PDF fallback helper
mkdir -p /root/genomics-stack/tools/renderer_e2e
cat > /root/genomics-stack/tools/renderer_e2e/pdf_fallback.sh <<'FB'
#!/usr/bin/env bash
set -euo pipefail
HTML="${1:?html input}"
PDF="${2:?pdf output}"
: "${WKHTMLTOPDF:=wkhtmltopdf}"
"$WKHTMLTOPDF" "$HTML" "$PDF"
echo "[pdf_fallback] wrote $PDF"
FB
chmod +x /root/genomics-stack/tools/renderer_e2e/pdf_fallback.sh

echo "[install] Done."
