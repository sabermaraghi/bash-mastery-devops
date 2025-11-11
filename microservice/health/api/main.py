# microservice/health/api/main.py
from fastapi import FastAPI
import os
import time

app = FastAPI(title="Health Microservice")

@app.get("/health")
def liveness():
    return {"status": "healthy", "time": time.time()}

@app.get("/ready")
def readiness():
    if os.path.exists("/tmp/ready"):
        return {"status": "ready"}
    return {"status": "not ready"}, 503
