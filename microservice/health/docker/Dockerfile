FROM python:3.12-slim
LABEL org.opencontainers.image.title="health-api" \
      org.opencontainers.image.version="1.0.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bash && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -u 1001 appuser

WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/main.py .
COPY scripts/health-monitor.sh scripts/
RUN chmod +x scripts/health-monitor.sh

USER appuser
EXPOSE 8000

# K8s Probes
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:8000/health/liveness || exit 1

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port 8000 & ./scripts/health-monitor.sh"]
