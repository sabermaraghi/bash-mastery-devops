# microservice/backup/api/main.py
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, validator
from typing import Literal, Optional
import subprocess
import os
import logging
from datetime import datetime

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backup-api")

app = FastAPI(
    title="Backup Microservice",
    description="Secure, encrypted, auditable backup orchestration with Bash engine",
    version="1.0.0",
    contact={"name": "DevOps Team", "email": "devops@example.com"},
    license_info={"name": "MIT"},
)

class BackupRequest(BaseModel):
    source: str = Field(..., example="/var/www/html", description="Source directory to backup")
    encryption: Literal["gpg", "none"] = Field("gpg", description="Encryption method")
    recipient: Optional[str] = Field(
        "devops@example.com",
        example="admin@company.com",
        description="GPG recipient email (required if encryption=gpg)"
    )
    retention_days: int = Field(30, ge=1, le=365, description="Keep backup for N days")

    @validator('recipient')
    def recipient_required(cls, v, values):
        if values.get('encryption') == 'gpg' and not v:
            raise ValueError('recipient is required when encryption=gpg')
        return v

@app.post("/backup", response_model=dict, status_code=status.HTTP_201_CREATED)
async def trigger_backup(req: BackupRequest):
    script_path = "/app/scripts/backup-orchestrator.sh"
    if not os.path.exists(script_path):
        logger.error("Orchestrator script not found")
        raise HTTPException(status_code=500, detail="Internal orchestrator missing")

    cmd = [
        "bash", script_path,
        req.source, req.encryption,
        req.recipient or "", str(req.retention_days)
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,  # 10 min max
            check=False
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Backup timeout after 10 minutes")

    if result.returncode != 0:
        logger.error(f"Backup failed: {result.stderr}")
        raise HTTPException(status_code=500, detail=f"Backup failed: {result.stderr}")

    backup_file = result.stdout.strip()
    logger.info(f"Backup completed: {backup_file}")

    return {
        "status": "success",
        "backup_file": backup_file,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "request_id": "backup-" + datetime.utcnow().strftime("%Y%m%d%H%M%S")
    }

@app.get("/health")
def health_check():
    return {"status": "healthy", "service": "backup-api", "timestamp": datetime.utcnow().isoformat() + "Z"}

@app.get("/")
def root():
    return {"message": "Backup Microservice API - POST /backup to trigger"}
