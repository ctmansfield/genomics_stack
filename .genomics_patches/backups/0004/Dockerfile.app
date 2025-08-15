# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder
WORKDIR /app
COPY pyproject.toml* requirements*.txt* /app/ 2>/dev/null || true
RUN python -m pip install -U pip && \
    if [ -f requirements.txt ]; then pip wheel --wheel-dir=/wheels -r requirements.txt; else pip wheel --wheel-dir=/wheels ruff black mypy pytest; fi

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN adduser --disabled-password --gecos "" app && mkdir -p /app && chown -R app:app /app
USER app
WORKDIR /app
COPY --from=builder /wheels /wheels
RUN python -m pip install --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY . /app
CMD ["python","-m","ingest_worker.main"]
