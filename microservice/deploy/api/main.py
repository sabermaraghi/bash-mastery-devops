# microservice/deploy/api/main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import subprocess
import os

app = FastAPI(title="Deploy Microservice", version="1.0.0")

class DeployRequest(BaseModel):
    version: str
    canary: bool = False

@app.post("/deploy")
async def deploy_app(req: DeployRequest):
    script = "/app/scripts/deploy-orchestrator.sh"
    if not os.path.exists(script):
        raise HTTPException(500, "Deploy script missing")

    cmd = ["bash", script, req.version, str(req.canary).lower()]
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        raise HTTPException(500, f"Deploy failed: {result.stderr}")

    return {"status": "deployed", "version": req.version, "mode": "canary" if req.canary else "full"}
