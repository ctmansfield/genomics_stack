source "$(dirname "$0")/../lib/overwrite.sh"
task_write_services() {
  say "Writing ingest service files"
  sudo mkdir -p /root/genomics-stack/ingest
  safe_write_file /root/genomics-stack/ingest/requirements.txt <<'EOF'
fastapi==0.111.0
uvicorn[standard]==0.30.1
python-multipart==0.0.9
psycopg[binary]==3.2.1
aiofiles==23.2.1
EOF
  safe_write_file /root/genomics-stack/ingest/Dockerfile <<'EOF'
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates curl tini && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt /app/
RUN pip install -r requirements.txt
COPY app.py /app/
ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8090"]
EOF
  # keep your working app.py you already have:
  [[ -f /root/genomics-stack/ingest/app.py ]] || safe_write_file /root/genomics-stack/ingest/app.py <<'EOF'
# (placeholder) You already have a working app.py from earlier steps
from fastapi import FastAPI
app = FastAPI()
@app.get("/healthz")
def health(): return {"ok": True}
EOF

  say "Writing ingest_worker files"
  sudo mkdir -p /root/genomics-stack/ingest_worker
  safe_write_file /root/genomics-stack/ingest_worker/requirements.txt <<'EOF'
psycopg[binary]==3.2.1
chardet==5.2.0
EOF
  safe_write_file /root/genomics-stack/ingest_worker/Dockerfile <<'EOF'
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends tzdata tini && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt /app/
RUN pip install -r requirements.txt
COPY worker.py /app/
ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["python","/app/worker.py"]
EOF
  [[ -f /root/genomics-stack/ingest_worker/worker.py ]] || safe_write_file /root/genomics-stack/ingest_worker/worker.py <<'EOF'
# (placeholder) You already have a working worker.py from earlier steps
print("worker placeholder")
EOF

  ok "Service files present"
}
register_task "services-write" "Write ingest/ingest_worker scaffolding (backup before overwrite)" task_write_services "Overwrites service files if missing."
