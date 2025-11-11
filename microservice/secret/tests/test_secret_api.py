import pytest
from fastapi.testclient import TestClient
from main import app
import os

client = TestClient(app)
os.environ["SECRET_API_TOKEN"] = "dev-token-123"

def test_rotate_aws():
    response = client.post("/rotate", headers={"Authorization": "Bearer dev-token-123"}, json={
        "secret_name": "db-pass",
        "provider": "aws",
        "region": "eu-central-1",
        "hsm_enabled": True
    })
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "rotated"
    assert "next_rotation" in data

def test_unauthorized():
    response = client.post("/rotate", json={})
    assert response.status_code == 401
