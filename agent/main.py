"""
Antigravity Bridge - Remote Agent
==================================
A secure FastAPI server that listens for commands from the Antigravity
mobile app and executes them in the local shell environment.

Run with:
  uvicorn main:app --host 0.0.0.0 --port 8742 --reload
"""

import os
import subprocess
import asyncio
import uuid
from datetime import datetime, timezone
from typing import Optional, List
import httpx

from fastapi import FastAPI, Depends, HTTPException, Header, status, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, messaging

load_dotenv()

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────
API_SECRET_TOKEN = os.getenv("API_SECRET_TOKEN", "")
AGENT_SHELL = os.getenv("AGENT_SHELL", "bash")
COMMAND_TIMEOUT_SEC = 60  # Hard kill any command that exceeds this
FIREBASE_KEY_PATH = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")

if not API_SECRET_TOKEN:
    raise RuntimeError("API_SECRET_TOKEN is not set. Copy .env.example to .env and fill it in.")

# ─────────────────────────────────────────────────────────────────────────────
# Firebase Initialization
# ─────────────────────────────────────────────────────────────────────────────
if FIREBASE_KEY_PATH and os.path.exists(FIREBASE_KEY_PATH):
    cred = credentials.Certificate(FIREBASE_KEY_PATH)
    firebase_admin.initialize_app(cred)
    print(f"🚀 Firebase initialized with key: {FIREBASE_KEY_PATH}")
else:
    print("⚠  Firebase not initialized. Specify FIREBASE_SERVICE_ACCOUNT_PATH in .env to enable Dings.")

# ─────────────────────────────────────────────────────────────────────────────
# In-memory job store (Phase 1 — upgradeable to Redis in Phase 4)
# ─────────────────────────────────────────────────────────────────────────────
jobs: dict[str, dict] = {}

# ─────────────────────────────────────────────────────────────────────────────
# App
# ─────────────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Antigravity Remote Agent",
    description="Secure command bridge between the Antigravity mobile app and your dev machine.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # Restrict to your Tailscale IP in prod
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────────────────────────────────────────────────────────
# Auth
# ─────────────────────────────────────────────────────────────────────────────
async def verify_token(x_api_token: Optional[str] = Header(default=None)):
    """Verify the secret token sent by the mobile app in every request."""
    if not x_api_token or x_api_token != API_SECRET_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing X-API-Token header.",
        )

# ─────────────────────────────────────────────────────────────────────────────
# Models
# ─────────────────────────────────────────────────────────────────────────────
class CommandRequest(BaseModel):
    command: str = Field(..., description="The shell command to execute.", examples=["git status"])
    working_dir: Optional[str] = Field(None, description="Optional working directory (defaults to home).")
    async_run: bool = Field(False, description="If True, runs in background and returns a job ID immediately.")

class CommandResult(BaseModel):
    job_id: str
    command: str
    stdout: str
    stderr: str
    exit_code: int
    started_at: str
    finished_at: str
    duration_ms: int

class JobStatus(BaseModel):
    job_id: str
    status: str   # "running" | "done" | "failed"
    result: Optional[CommandResult] = None

class NotificationRequest(BaseModel):
    title: str
    body: str
    token: Optional[str] = Field(None, description="Target device FCM token. If None, sends to 'all' topic.")

class WorkflowRun(BaseModel):
    id: int
    name: str
    status: str
    conclusion: Optional[str]
    repo: str
    url: str
    created_at: str

# ─────────────────────────────────────────────────────────────────────────────
# Notification Helper
# ─────────────────────────────────────────────────────────────────────────────
async def send_ding(title: str, body: str, token: Optional[str] = None):
    """Send a push notification via Firebase."""
    if not firebase_admin._apps:
        print(f"Ding suppressed (Firebase not ready): {title} - {body}")
        return

    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        token=token,
        topic="all" if not token else None,
    )
    
    try:
        response = messaging.send(message)
        print(f"Ding sent successfully: {response}")
    except Exception as e:
        print(f"Failed to send Ding: {e}")

# ─────────────────────────────────────────────────────────────────────────────
# Execution Engine
# ─────────────────────────────────────────────────────────────────────────────
async def _run_command(job_id: str, command: str, cwd: Optional[str]):
    """Execute a shell command and store the result in the jobs dict."""
    jobs[job_id]["status"] = "running"
    started_at = datetime.now(timezone.utc)

    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd or os.path.expanduser("~"),
            executable=AGENT_SHELL if AGENT_SHELL != "powershell" else None,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=COMMAND_TIMEOUT_SEC)
        except asyncio.TimeoutError:
            proc.kill()
            stdout_b, stderr_b = b"", b"[AGENT] Command killed - exceeded timeout."
            proc.returncode = -1

        finished_at = datetime.now(timezone.utc)
        duration_ms = int((finished_at - started_at).total_seconds() * 1000)

        result = CommandResult(
            job_id=job_id,
            command=command,
            stdout=stdout_b.decode("utf-8", errors="replace"),
            stderr=stderr_b.decode("utf-8", errors="replace"),
            exit_code=proc.returncode,
            started_at=started_at.isoformat(),
            finished_at=finished_at.isoformat(),
            duration_ms=duration_ms,
        )
        jobs[job_id]["status"] = "done" if proc.returncode == 0 else "failed"
        jobs[job_id]["result"] = result

    except Exception as exc:
        finished_at = datetime.now(timezone.utc)
        jobs[job_id]["status"] = "failed"
        jobs[job_id]["result"] = CommandResult(
            job_id=job_id,
            command=command,
            stdout="",
            stderr=str(exc),
            exit_code=-1,
            started_at=started_at.isoformat(),
            finished_at=finished_at.isoformat(),
            duration_ms=0,
        )

# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health():
    """Quick liveness check. No auth required for uptime monitors."""
    return {"status": "ok", "agent": "Antigravity Remote Agent", "version": "0.1.0"}


@app.post("/command", response_model=JobStatus, tags=["Execution"], dependencies=[Depends(verify_token)])
async def run_command_endpoint(req: CommandRequest, background_tasks: BackgroundTasks):
    """
    Execute a shell command on the remote machine.

    - **sync** (`async_run=false`): Blocks until done, returns full result.
    - **async** (`async_run=true`): Returns a `job_id` immediately. Poll `/jobs/{job_id}` for the result.
    """
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "result": None}

    if req.async_run:
        background_tasks.add_task(_run_command, job_id, req.command, req.working_dir)
        return JobStatus(job_id=job_id, status="queued")
    else:
        await _run_command(job_id, req.command, req.working_dir)
        return JobStatus(job_id=job_id, status=jobs[job_id]["status"], result=jobs[job_id]["result"])


@app.get("/jobs/{job_id}", response_model=JobStatus, tags=["Execution"], dependencies=[Depends(verify_token)])
async def get_job_status(job_id: str):
    """Poll the status of an async command execution."""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found.")
    job = jobs[job_id]
    return JobStatus(job_id=job_id, status=job["status"], result=job.get("result"))


@app.get("/jobs", tags=["Execution"], dependencies=[Depends(verify_token)])
async def list_jobs():
    """List all jobs in the current session (cleared on restart)."""
    return [
        {"job_id": jid, "status": jdata["status"]}
        for jid, jdata in jobs.items()
    ]


@app.post("/notify", tags=["Notifications"], dependencies=[Depends(verify_token)])
async def notify_endpoint(req: NotificationRequest):
    """Send a manual push notification to the mobile app."""
    await send_ding(req.title, req.body, req.token)
    return {"status": "sent"}


@app.get("/workflows", tags=["GitHub"], dependencies=[Depends(verify_token)])
async def get_github_workflows(owner: str, repo: str):
    """Fetch recent workflow runs from GitHub for a specific repository."""
    if not GITHUB_TOKEN:
        raise HTTPException(status_code=400, detail="GITHUB_TOKEN not configured on agent.")
    
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs?per_page=10"
    headers = {
        "Authorization": f"token {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            
            runs = []
            for run in data.get("workflow_runs", []):
                runs.append(WorkflowRun(
                    id=run["id"],
                    name=run["name"],
                    status=run["status"],
                    conclusion=run["conclusion"],
                    repo=f"{owner}/{repo}",
                    url=run["html_url"],
                    created_at=run["created_at"]
                ))
            return runs
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))


@app.delete("/jobs/{job_id}", tags=["Execution"], dependencies=[Depends(verify_token)])
async def clear_job(job_id: str):
    """Remove a job from the store."""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found.")
    del jobs[job_id]
    return {"deleted": job_id}
