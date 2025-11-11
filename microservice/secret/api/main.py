# microservice/secret/api/main.py
from fastapi import FastAPI, HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, SecretStr
from typing import Literal, Optional
import subprocess
import os
import logging
import json
from datetime import datetime
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("secret-api")

app = FastAPI(
    title="Secret Management Microservice",
    description="Multi-cloud secret rotation with audit, HSM, and compliance",
    version="1.0.0",
    contact={"name": "Security Team", "email": "security@example.com"}
)

# Mock token auth (in prod: OIDC/JWT)
security = HTTPBearer()

class RotateRequest(BaseModel):
    secret_name: str = Field(..., example="db-password-prod")
    provider: Literal["aws", "gcp", "azure", "hashicorp-vault"] = "aws"
    region: Optional[str] = Field(None, example="eu-central-1")
    hsm_enabled: bool = Field(False, description="Use Hardware Security Module")
    rotation_interval_days: int = Field(90, ge=1, le=365)

class SecretResponse(BaseModel):
    secret_id: str
    version: str
    rotated_at: str
    next_rotation: str
    provider: str
    status: Literal["rotated", "failed", "skipped"]

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    if token != os.getenv("SECRET_API_TOKEN", "dev-token-123"):
        raise HTTPException(status_code=401, detail="Invalid token")
    return token

@app.post("/rotate", response_model=SecretResponse, dependencies=[Depends(verify_token)])
async def rotate_secret(req: RotateRequest):
    script = "/app/scripts/secret-rotator.sh"
    if not os.path.exists(script):
        raise HTTPException(500, "Rotator script missing")

    cmd = [
        "bash", script,
        req.secret_name, req.provider,
        req.region or "", str(int(req.hsm_enabled)),
        str(req.rotation_interval_days)
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Rotation timeout")

    if result.returncode != 0:
        logger.error(f"Rotation failed: {result.stderr}")
        raise HTTPException(500, f"Rotation failed: {result.stderr}")

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        output = {"raw": result.stdout}

    audit_log(
        action="rotate",
        secret=req.secret_name,
        provider=req.provider,
        status="success",
        user="api-client",
        request_id=str(uuid.uuid4())
    )

    return SecretResponse(
        secret_id=output.get("secret_id", req.secret_name),
        version=output.get("version", "v2"),
        rotated_at=datetime.utcnow().isoformat() + "Z",
        next_rotation=output.get("next_rotation", "unknown"),
        provider=req.provider,
        status="rotated"
    )

@app.get("/health")
def health():
    return {"status": "healthy", "service": "secret-api"}

def audit_log(action: str, secret: str, provider: str, status: str, user: str, request_id: str):
    log_entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "action": action,
        "secret": secret,
        "provider": provider,
        "status": status,
        "user": user,
        "request_id": request_id,
        "compliance": "GDPR/NIS2/DORA"
    }
    with open("/var/log/secret-audit.log", "a") as f:
        f.write(json.dumps(log_entry) + "\n")
    logger.info(f"AUDIT: {log_entry}")
