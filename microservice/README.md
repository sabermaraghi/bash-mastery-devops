# Build & Run

## Backup-api Microservice

cd microservice/backup/docker
./build.sh
podman run -d -p 8000:8000 --name backup-api localhost/backup-api:v1.0.0

# Test API
curl -X POST http://localhost:8000/backup \
  -H "Content-Type: application/json" \
  -d '{"source": "/app", "encryption": "none", "retention_days": 1}'



## Deploy-api Microservice

cd microservice/deploy/docker
./build.sh
podman run -d -p 8001:8000 localhost/deploy-api:v1.0.0

# Test

curl -X POST http://localhost:8001/deploy \
  -H "Content-Type: application/json" \
  -d '{"image": "nginx:latest", "strategy": "blue-green", "health_endpoint": "/health"}'




## Health-api Microservice

cd microservice/health/docker
./build.sh
podman run -d -p 8002:8000 localhost/health-api:v1.0.0

# Test Probes

curl http://localhost:8002/health/liveness
curl http://localhost:8002/health/readiness
curl http://localhost:8002/metrics





## Secret-api Microservice

cd microservice/secret/docker
./build.sh
podman run -d -p 8003:8000 -e SECRET_API_TOKEN=dev-token-123 localhost/secret-api:v1.0.0

# Test

curl -X POST http://localhost:8003/rotate \
  -H "Authorization: Bearer dev-token-123" \
  -H "Content-Type: application/json" \
  -d '{"secret_name": "test", "provider": "aws"}'
