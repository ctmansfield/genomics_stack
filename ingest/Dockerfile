FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      tzdata ca-certificates curl tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt /app/
RUN pip install -r requirements.txt

COPY app.py /app/

# Non-root for safety
RUN useradd -m -u 1000 appuser
USER appuser

ENV PORT=8090
EXPOSE 8090
ENTRYPOINT ["/usr/bin/tini","-g","--"]
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8090","--proxy-headers"]
