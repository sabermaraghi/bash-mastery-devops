FROM python:3.12-slim
LABEL org.opencontainers.image.title="deploy-api" \
      org.opencontainers.image.version="1.0.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq podman && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -u 1001 appuser

WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/main.py .
COPY scripts/deploy-orchestrator.sh scripts/
RUN chmod +x scripts/deploy-orchestrator.sh

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
