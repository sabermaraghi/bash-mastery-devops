# microservice/secret/api/main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import subprocess

app = FastAPI(title="Secret Rotator")

class RotateRequest(BaseModel):
    name: str

@app.post("/rotate")
def rotate_secret(req: RotateRequest):
    cmd = ["bash", "/app/scripts/rotate-secret.sh", req.name]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise HTTPException(500, result.stderr)
    return {"rotated": req.name, "new_key": result.stdout.strip()}

