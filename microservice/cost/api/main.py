from fastapi import FastAPI
from typing import Optional
import subprocess
import json

app = FastAPI(title="Cost Analyzer")

@app.get("/cost")
def get_cost(days: Optional[int] = 7):
    cmd = ["bash", "/app/scripts/cost-report.sh", str(days)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return {"error": result.stderr}, 500
    return json.loads(result.stdout)
