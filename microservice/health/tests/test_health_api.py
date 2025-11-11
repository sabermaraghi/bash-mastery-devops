from fastapi.testclient import TestClient
from main import app, health_state
import time

client = TestClient(app)

def test_liveness():
    response = client.get("/health/liveness")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_readiness():
    response = client.get("/health/readiness")
    assert response.status_code == 200

def test_startup_delay():
    # Reset startup
    health_state["startup_complete"] = False
    health_state["startup_start"] = time.time() - 20
    response = client.get("/health/startup")
    assert response.status_code == 200

def test_metrics():
    client.get("/health/liveness")
    response = client.get("/metrics")
    assert response.json()["health_requests_total"] >= 1
