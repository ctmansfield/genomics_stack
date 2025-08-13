source "$(dirname "$0")/../lib/overwrite.sh"
task_write_compose() {
  local y="/root/genomics-stack/compose.yml"
  say "Writing compose.yml (idempotent)"
  safe_write_file "$y" <<'YAML'
services:
  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - /mnt/nas_storage/genomics-stack/db_data:/var/lib/postgresql/data
      - /mnt/nas_storage/genomics-stack/init:/docker-entrypoint-initdb.d:ro
    ports:
      - "5433:5432"
    healthcheck:
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10

  hasura:
    image: hasura/graphql-engine:v2.40.0
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      HASURA_GRAPHQL_DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
      HASURA_GRAPHQL_ENABLE_CONSOLE: "true"
      HASURA_GRAPHQL_ADMIN_SECRET: ${HASURA_GRAPHQL_ADMIN_SECRET}
      HASURA_GRAPHQL_UNAUTHORIZED_ROLE: "public"
      HASURA_GRAPHQL_JWT_SECRET: ${HASURA_GRAPHQL_JWT_SECRET}
    volumes:
      - /mnt/nas_storage/genomics-stack/hasura_metadata:/hasura-metadata
    ports: [ "8080:8080" ]

  metabase:
    image: metabase/metabase:latest
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      MB_DB_FILE: /metabase-data/metabase.db
    volumes:
      - /mnt/nas_storage/genomics-stack/metabase_data:/metabase-data
    ports: [ "3000:3000" ]

  pgadmin:
    image: dpage/pgadmin4:8
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - /mnt/nas_storage/genomics-stack/pgadmin_data:/var/lib/pgadmin
    ports: [ "5050:80" ]

  ingest:
    build:
      context: /root/genomics-stack/ingest
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      PGHOST: db
      PGPORT: 5432
      PGUSER: ${POSTGRES_USER}
      PGPASSWORD: ${POSTGRES_PASSWORD}
      PGDATABASE: ${POSTGRES_DB}
      DATA_DIR: /data
      UPLOAD_TOKEN: ${UPLOAD_TOKEN}
      MAX_UPLOAD_BYTES: "2147483648"
    volumes:
      - /mnt/nas_storage/genomics-stack/uploads:/data
    ports: [ "8090:8090" ]

  ingest_worker:
    build:
      context: /root/genomics-stack/ingest_worker
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      PGHOST: db
      PGPORT: 5432
      PGUSER: ${POSTGRES_USER}
      PGPASSWORD: ${POSTGRES_PASSWORD}
      PGDATABASE: ${POSTGRES_DB}
      DATA_DIR: /data
      POLL_SEC: "3"
    volumes:
      - /mnt/nas_storage/genomics-stack/uploads:/data
YAML
  ok "compose.yml written"
}
register_task "compose-write" "Write compose.yml (with backups)" task_write_compose "Overwrites compose.yml after backing it up."
