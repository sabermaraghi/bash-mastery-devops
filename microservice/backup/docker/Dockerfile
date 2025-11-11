# Multi-stage, minimal, secure
FROM python:3.12-slim AS builder
WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
LABEL org.opencontainers.image.title="backup-api" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.authors="DevOps Team"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq gnupg tar ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -u 1001 appuser && \
    mkdir -p /backups /var/log /var/run && \
    chown appuser:appuser /backups /var/log /var/run

WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY api/main.py .
COPY scripts/backup-orchestrator.sh scripts/
RUN chmod +x scripts/backup-orchestrator.sh && \
    chown -R appuser:appuser /app

USER appuser
VOLUME /backups
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
