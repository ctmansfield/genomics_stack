#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

ENV_FILE=".env"
touch "$ENV_FILE"

# ensure .env stays out of git
if [ -f .gitignore ]; then
  grep -qxF '/.env' .gitignore || echo '/.env' >> .gitignore
else
  echo '/.env' > .gitignore
fi

# remove any existing lines for these keys
for key in HASURA_GRAPHQL_ADMIN_SECRET HASURA_GRAPHQL_JWT_SECRET METABASE_DB_FILE; do
  sed -i -E "/^${key}=.*/d" "$ENV_FILE"
done

# append your actual values
cat >> "$ENV_FILE" <<'EOF'
HASURA_GRAPHQL_ADMIN_SECRET=43cbe604478f431c858691e4e990ac77d88cf828ed0d7789743af5d3c0cfc19e
HASURA_GRAPHQL_JWT_SECRET={"type":"HS256","key":"63895fa42a2c7dabf39e423ac99be6ee280f1a44755f267d4e6fbf309e58e8912c9c59f9496b7e7d13b2bceab0d81a71a5fa936e7f4de74fe667b392c5d0147b"}
METABASE_DB_FILE=/metabase-data/metabase.db
EOF

echo "[ok] wrote ${ENV_FILE} (Hasura + Metabase)"
