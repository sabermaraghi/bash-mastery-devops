import pytest
from fastapi.testclient import TestClient
from main import app
import os
import tempfile

client = TestClient(app)

def test_backup_success():
    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["BACKUP_DIR"] = tmpdir  # Mock
        response = client.post("/backup", json={
            "source": "/app",
            "encryption": "none",
            "retention_days": 1
        })
        assert response.status_code == 201
        data = response.json()
        assert "backup_file" in data
        assert data["status"] == "success"

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
