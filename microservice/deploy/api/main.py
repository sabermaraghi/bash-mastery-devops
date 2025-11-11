# microservice/deploy/api/main.py
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, validator
from typing import Literal, Optional
import subprocess
import os
import logging
from datetime import datetime
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("deploy-api")

app = FastAPI(
    title="Deploy Microservice",
    description="Zero-downtime blue-green + canary deployment with auto-rollback",
    version="1.0.0",
    contact={"name": "SRE Team", "email": "sre@example.com"}
)

class DeployRequest(BaseModel):
    image: str = Field(..., example="ghcr.io/yourorg/app:v2.1.0")
    strategy: Literal["blue-green", "canary"] = "blue-green"
    canary_percentage: Optional[int] = Field(
        None, ge=1, le=100, description="Only for canary strategy"
    )
    health_endpoint: str = Field("/health", example="/health")
    timeout_seconds: int = Field(300, ge=60, le=1800)

    @validator('canary_percentage')
    def validate_canary(cls, v, values):
        if values.get('strategy') == 'canary' and v is None:
            raise ValueError('canary_percentage required for canary strategy')
        return v

@app.post("/deploy", status_code=status.HTTP_202_ACCEPTED)
async def trigger_deploy(req: DeployRequest):
    script = "/app/scripts/deploy-orchestrator.sh"
    if not os.path.exists(script):
        raise HTTPException(500, "Deploy orchestrator missing")

    cmd = [
        "bash", script,
        req.image, req.strategy,
        str(req.canary_percentage or 0),
        req.health_endpoint, str(req.timeout_seconds)
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=req.timeout_seconds + 60)
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Deployment timeout")

    if result.returncode != 0:
        logger.error(f"Deploy failed: {result.stderr}")
        raise HTTPException(500, f"Deploy failed: {result.stderr}")

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        output = {"raw": result.stdout}

    return {
        "status": "deployed",
        "strategy": req.strategy,
        "image": req.image,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "details": output
    }

@app.get("/health")
def health():
    return {"status": "healthy", "service": "deploy-api"}
