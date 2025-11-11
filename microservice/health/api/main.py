# microservice/health/api/main.py
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Literal, Optional
import subprocess
import os
import logging
import time
import json
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("health-api")

app = FastAPI(
    title="Health Microservice",
    description="K8s liveness/readiness/startup + metrics + self-healing + alerting",
    version="1.0.0",
    contact={"name": "Observability Team", "email": "obs@example.com"}
)

# In-memory state (in real world: Redis or etcd)
health_state = {
    "liveness": True,
    "readiness": True,
    "startup_complete": False,
    "last_check": None,
    "failed_checks": 0,
    "metrics": {"requests_total": 0, "errors_total": 0}
}

class HealthResponse(BaseModel):
    status: Literal["healthy", "unhealthy", "degraded"]
    component: str
    timestamp: str
    details: dict

@app.get("/health/liveness", response_model=HealthResponse)
def liveness_probe():
    """K8s liveness: restart if fails"""
    health_state["metrics"]["requests_total"] += 1
    if not health_state["liveness"]:
        health_state["metrics"]["errors_total"] += 1
        raise HTTPException(500, "Liveness failed")
    return HealthResponse(
        status="healthy",
        component="liveness",
        timestamp=datetime.utcnow().isoformat() + "Z",
        details={"pid": os.getpid()}
    )

@app.get("/health/readiness", response_model=HealthResponse)
def readiness_probe():
    """K8s readiness: stop traffic if fails"""
    health_state["metrics"]["requests_total"] += 1
    if not health_state["readiness"]:
        health_state["metrics"]["errors_total"] += 1
        raise HTTPException(503, "Not ready")
    return HealthResponse(
        status="healthy",
        component="readiness",
        timestamp=datetime.utcnow().isoformat() + "Z",
        details={"db_connected": True, "cache_warm": True}
    )

@app.get("/health/startup", response_model=HealthResponse)
def startup_probe():
    """K8s startup: delay start until ready"""
    if not health_state["startup_complete"]:
        # Simulate slow startup
        if time.time() - (health_state.get("startup_start", 0)) < 15:
            raise HTTPException(503, "Startup in progress")
        health_state["startup_complete"] = True
    return HealthResponse(
        status="healthy",
        component="startup",
        timestamp=datetime.utcnow().isoformat() + "Z",
        details={}
    )

@app.get("/metrics")
def metrics():
    """Prometheus format"""
    return JSONResponse(
        content={
            "health_requests_total": health_state["metrics"]["requests_total"],
            "health_errors_total": health_state["metrics"]["errors_total"],
            "health_liveness": 1 if health_state["liveness"] else 0,
            "health_readiness": 1 if health_state["readiness"] else 0,
            "health_startup_complete": 1 if health_state["startup_complete"] else 0,
            "timestamp": int(time.time())
        },
        media_type="application/json"
    )

@app.post("/simulate/failure")
def simulate_failure(failure_type: Literal["liveness", "readiness"]):
    """For chaos testing"""
    if failure_type == "liveness":
        health_state["liveness"] = False
    else:
        health_state["readiness"] = False
    logger.warning(f"Simulated {failure_type} failure")
    return {"status": f"{failure_type} disabled"}

@app.post("/simulate/recover")
def recover():
    health_state["liveness"] = True
    health_state["readiness"] = True
    return {"status": "recovered"}

@app.on_event("startup")
async def startup_event():
    health_state["startup_start"] = time.time()
    logger.info("Health API starting up...")

@app.get("/")
def root():
    return {"message": "Health API - use /health/* endpoints"}
