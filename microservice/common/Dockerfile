FROM python:3.12-slim AS base
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq awscli gnupg tar && \
    rm -rf /var/lib/apt/lists/*

FROM base AS builder
WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY api/main.py .
COPY scripts/*.sh scripts/
RUN chmod +x scripts/*.sh
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
