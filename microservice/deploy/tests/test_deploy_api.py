from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_deploy_blue_green():
    response = client.post("/deploy", json={
        "image": "nginx:latest",
        "strategy": "blue-green",
        "health_endpoint": "/health"
    })
    assert response.status_code == 202
    data = response.json()
    assert data["status"] == "deployed"
    assert data["strategy"] == "blue-green"

def test_deploy_canary():
    response = client.post("/deploy", json={
        "image": "nginx:latest",
        "strategy": "canary",
        "canary_percentage": 10,
        "health_endpoint": "/health"
    })
    assert response.status_code == 202
