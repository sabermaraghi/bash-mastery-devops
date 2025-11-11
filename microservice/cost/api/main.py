# microservice/cost/api/main.py
from fastapi import FastAPI, HTTPException, status, Depends
from fastapi.security import HTTPBearer
from pydantic import BaseModel, Field
from typing import Literal, Optional, List
import subprocess
import os
import logging
import json
from datetime import datetime, timedelta
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("cost-api")

app = FastAPI(
    title="Cost Intelligence Microservice",
    description="Multi-cloud cost analysis, forecasting, budget alerts (FinOps)",
    version="1.0.0",
    contact={"name": "FinOps Team", "email": "finops@example.com"}
)

security = HTTPBearer()

class CostQuery(BaseModel):
    provider: Literal["aws", "gcp", "azure", "all"] = "aws"
    days: int = Field(30, ge=1, le=365)
    granularity: Literal["daily", "monthly"] = "daily"
    forecast_days: Optional[int] = Field(None, ge=1, le=90)
    budget_threshold: Optional[float] = Field(None, gt=0)

class CostResponse(BaseModel):
    total_cost: float
    currency: str
    period: str
    forecast: Optional[dict] = None
    alert: Optional[str] = None
    services: List[dict]

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    if token != os.getenv("COST_API_TOKEN", "finops-token-123"):
        raise HTTPException(401, "Invalid token")
    return token

@app.post("/analyze", response_model=CostResponse, dependencies=[Depends(verify_token)])
async def analyze_cost(query: CostQuery):
    script = "/app/scripts/cost-analyzer.sh"
    if not os.path.exists(script):
        raise HTTPException(500, "Cost analyzer missing")

    cmd = [
        "bash", script,
        query.provider, str(query.days),
        query.granularity,
        str(query.forecast_days or 0),
        str(query.budget_threshold or 0)
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Cost analysis timeout")

    if result.returncode != 0:
        logger.error(f"Analysis failed: {result.stderr}")
        raise HTTPException(500, f"Analysis failed: {result.stderr}")

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        output = {"raw": result.stdout}

    # Log to audit
    audit_log(
        action="cost_analysis",
        provider=query.provider,
        days=query.days,
        user="api-client",
        request_id=str(uuid.uuid4())
    )

    return CostResponse(
        total_cost=output.get("total_cost", 0.0),
        currency=output.get("currency", "EUR"),
        period=output.get("period", f"Last {query.days} days"),
        forecast=output.get("forecast"),
        alert=output.get("alert"),
        services=output.get("top_services", [])
    )

@app.get("/health")
def health():
    return {"status": "healthy", "service": "cost-api"}

def audit_log(**kwargs):
    entry = {"timestamp": datetime.utcnow().isoformat() + "Z", **kwargs}
    with open("/var/log/cost-audit.log", "a") as f:
        f.write(json.dumps(entry) + "\n")
    logger.info(f"COST AUDIT: {entry}")
