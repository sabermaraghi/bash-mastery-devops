FROM python:3.12-slim
LABEL org.opencontainers.image.title="cost-api" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.description="FinOps cost intelligence"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq bc awscli && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -u 1001 appuser && \
    mkdir -p /var/log /var/run && \
    chown appuser:appuser /var/log /var/run

WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/main.py .
COPY scripts/cost-analyzer.sh scripts/
RUN chmod +x scripts/cost-analyzer.sh

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
