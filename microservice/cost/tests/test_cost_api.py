from fastapi.testclient import TestClient
from main import app
import os

client = TestClient(app)
os.environ["COST_API_TOKEN"] = "finops-token-123"

def test_analyze_aws():
    response = client.post("/analyze", headers={"Authorization": "Bearer finops-token-123"}, json={
        "provider": "aws",
        "days": 7,
        "budget_threshold": 100.0
    })
    assert response.status_code == 200
    data = response.json()
    assert "total_cost" in data
    assert data["currency"] == "EUR"
