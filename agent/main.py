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

import json
from fastapi import FastAPI, Depends, HTTPException, Header, status, BackgroundTasks, Request, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse
from pydantic import BaseModel, Field
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, messaging, firestore
import google.generativeai as genai

load_dotenv()

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────
API_SECRET_TOKEN = os.getenv("API_SECRET_TOKEN", "")
AGENT_SHELL = os.getenv("AGENT_SHELL", "bash")
COMMAND_TIMEOUT_SEC = 60  # Hard kill any command that exceeds this
FIREBASE_KEY_PATH = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
DEVICE_NAME = os.getenv("DEVICE_NAME", "Remote Bridge Machine")
PROJECTS_ROOT = os.getenv("PROJECTS_ROOT", os.path.expanduser("~"))

if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)

if not API_SECRET_TOKEN:
    raise RuntimeError("API_SECRET_TOKEN is not set. Copy .env.example to .env and fill it in.")

# ─────────────────────────────────────────────────────────────────────────────
# Firebase Initialization
# ─────────────────────────────────────────────────────────────────────────────
if FIREBASE_KEY_PATH and os.path.exists(FIREBASE_KEY_PATH):
    cred = credentials.Certificate(FIREBASE_KEY_PATH)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print(f"🚀 Firebase + Firestore initialized with key: {FIREBASE_KEY_PATH}")
else:
    db = None
    print("⚠  Firebase not initialized. Specify FIREBASE_SERVICE_ACCOUNT_PATH in .env to enable Dings and Cloud Logs.")

# ─────────────────────────────────────────────────────────────────────────────
# In-memory job store (Phase 1 — upgradeable to Redis in Phase 4)
# ─────────────────────────────────────────────────────────────────────────────
jobs: dict[str, dict] = {}
monitored_workflows: dict[int, str] = {} # workflow_id: last_status
approvals: dict[str, dict] = {} # approval_id: {"event": asyncio.Event(), "result": bool}
log_listeners: List[asyncio.Queue] = []
log_history: List[dict] = []

async def agent_log(message: str, type: str = "info", source: str = "system"):
    """Helper to print logs and broadcast them to all connected SSE listeners."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] [{source.upper()}] {message}")
    
    log_data = {"type": type, "message": message, "timestamp": timestamp, "source": source}
    
    if len(log_history) > 100:
        log_history.pop(0)

    # Backup to Cloud (Firestore)
    if db:
        try:
            # We use an async wrapper or execute in thread since Firestore SDK is sync usually 
            # but for simplicity in this agent we'll do it sync for now as it's fast
            db.collection("logs").add({
                **log_data,
                "server_timestamp": firestore.SERVER_TIMESTAMP
            })
        except Exception as e:
            print(f"Error saving to cloud: {e}")
    
    # Broadcast to all active listeners
    for queue in log_listeners[:]: # Using a copy to avoid mutation errors
        await queue.put(log_data)

# Ensure we log the startup
asyncio.create_task(agent_log("🚀 Antigravity Agent starting up..."))

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

async def check_active_build(owner: str, repo: str) -> Optional[dict]:
    """Helper to check if there is an active GitHub Action run."""
    if not GITHUB_TOKEN: return None
    gh_headers = {"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json", "User-Agent": "AntigravityBridgeAgent"}
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"https://api.github.com/repos/{owner}/{repo}/actions/runs?per_page=1", headers=gh_headers)
            if resp.status_code == 200:
                runs = resp.json().get("workflow_runs", [])
                if runs and runs[0]["status"] in ["in_progress", "queued", "requested"]:
                    return {"id": runs[0]["id"], "status": runs[0]["status"], "url": runs[0]["html_url"]}
        except: pass
    return None

# ─────────────────────────────────────────────────────────────────────────────
# Auth
# ─────────────────────────────────────────────────────────────────────────────
async def verify_token(x_api_token: Optional[str] = Header(default=None)):
    """Verify the secret token sent by the mobile app in every request."""
    if not x_api_token:
        await agent_log("❌ Security: Missing X-API-Token header", "error")
        raise HTTPException(status_code=401, detail="Missing X-API-Token header.")
    
    if x_api_token != API_SECRET_TOKEN:
        await agent_log(f"❌ Security: Invalid Token Attempt (Received: {x_api_token[:5]}...)", "error")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid X-API-Token header.",
        )

# ─────────────────────────────────────────────────────────────────────────────
# Models
# ─────────────────────────────────────────────────────────────────────────────
class CommandRequest(BaseModel):
    command: str = Field(..., description="The shell command to execute.", examples=["git status"])
    working_dir: Optional[str] = Field(None, description="Optional working directory (defaults to home).")
    async_run: bool = Field(False, description="If True, runs in background and returns a job ID immediately.")
    context_repo: Optional[str] = Field(None, description="The repository context for this command.")
    context_chat_id: Optional[str] = Field(None, description="The specific Gemini chat thread ID.")

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

class ChatRequest(BaseModel):
    message: str
    context_repo: Optional[str] = None
    context_chat_id: Optional[str] = "default"
    model_id: Optional[str] = "gemini-1.5-flash"

class WorkflowRun(BaseModel):
    id: int
    name: str
    status: str
    conclusion: Optional[str]
    repo: str
    url: str
    visibility: str # "public" or "private"
    created_at: str

class GitHubRepo(BaseModel):
    id: int
    name: str
    full_name: str
    owner: str
    is_org: bool
    visibility: str # "public" or "private"
    description: Optional[str]
    url: str
    updated_at: str

class IntentRequest(BaseModel):
    intent: str
    params: Optional[dict] = {}
    context_repo: Optional[str] = Field(None, description="The repository context for this intent.")
    context_chat_id: Optional[str] = Field(None, description="The specific Gemini chat thread ID.")

class ModelQuota(BaseModel):
    name: str           # e.g. "Claude 3.5 Sonnet"
    model_id: str       # e.g. "claude-3-5-sonnet-20240620"
    used_tokens: int
    total_tokens: int
    reset_at: str       # ISO timestamp
    reset_seconds: int  # Seconds until reset

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

async def request_approval(title: str, body: str, token: Optional[str] = None) -> bool:
    """Send a notification and wait for the user to tap 'Accept' or 'Reject' on their phone."""
    approval_id = str(uuid.uuid4())
    event = asyncio.Event()
    
    approvals[approval_id] = {
        "event": event,
        "result": False,
        "title": title,
        "body": body
    }

    # Send notification with data payload for the app to recognize as an approval request
    if firebase_admin._apps:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={
                "type": "approval_request",
                "approval_id": approval_id,
            },
            token=token,
            topic="all" if not token else None,
        )
        messaging.send(message)
    else:
        print(f"Approval Requested (No Firebase): {title} - {body} [ID: {approval_id}]")

    # Wait for the user to respond via the /approve endpoint
    try:
        await asyncio.wait_for(event.wait(), timeout=300) # 5 minute timeout
        return approvals[approval_id]["result"]
    except asyncio.TimeoutError:
        return False
    finally:
        if approval_id in approvals:
            del approvals[approval_id]

# ─────────────────────────────────────────────────────────────────────────────
# Path Resolver
# ─────────────────────────────────────────────────────────────────────────────
def resolve_repo_path(context_repo: Optional[str]) -> str:
    """Resolve a GitHub repo name to a local path in PROJECTS_ROOT."""
    if not context_repo or "/" not in context_repo:
        return PROJECTS_ROOT
    
    # Extract just the repo name (e.g. Gravity2Phone from THEAMATEURSWAMI/Gravity2Phone)
    repo_name = context_repo.split("/")[-1]
    local_path = os.path.join(PROJECTS_ROOT, repo_name)
    
    if os.path.exists(local_path):
        return local_path
    return PROJECTS_ROOT

# ─────────────────────────────────────────────────────────────────────────────
# Execution Engine
# ─────────────────────────────────────────────────────────────────────────────
async def _run_command(job_id: str, command: str, context_repo: Optional[str] = None):
    """Execute a shell command and store the result in the jobs dict."""
    jobs[job_id]["status"] = "running"
    started_at = datetime.now(timezone.utc)
    
    cwd = resolve_repo_path(context_repo)

    await agent_log(f"💻 Executing [{os.path.basename(cwd)}]: {command}")
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
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

        if stdout_b:
            await agent_log(f"Terminal Output:\n{stdout_b.decode('utf-8', errors='replace')[:500]}...", "info", "terminal")
        if stderr_b:
            await agent_log(f"Terminal Error:\n{stderr_b.decode('utf-8', errors='replace')[:500]}...", "error", "terminal")

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
        
        status_icon = "✅" if proc.returncode == 0 else "❌"
        await agent_log(f"{status_icon} Command finished (Exit: {proc.returncode})", "success" if proc.returncode == 0 else "error")

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
# Intent Engine
# ─────────────────────────────────────────────────────────────────────────────
async def handle_intent(intent: str, params: dict, background_tasks: BackgroundTasks):
    """Map natural language intents to complex shell scripts."""
    if intent == "update-site":
        # Example using the new interactive system
        await agent_log(f"🧠 Intent detected: {intent}")
        should_proceed = await request_approval(
            "🚀 Deployment Request", 
            "Execute 'git pull && npm install && npm run build && firebase deploy'?"
        )
        
        if not should_proceed:
            return {"status": "rejected"}

        command = "git pull; npm install; npm run build; firebase deploy"
        
        # We run this in the background and notify when done
        job_id = str(uuid.uuid4())
        jobs[job_id] = {"status": "queued", "result": None}
        
        async def deploy_with_notify(jid: str, cmd: str):
            await send_ding("🚀 Deployment Started", "Executing site update pipeline...")
            await _run_command(jid, cmd, None)
            result = jobs[jid]["result"]
            if jobs[jid]["status"] == "done":
                await send_ding("✅ Deployment Success", "Your site is live!")
            else:
                await send_ding("❌ Deployment Failed", f"Error code: {result.exit_code}")

        background_tasks.add_task(deploy_with_notify, job_id, command)
        return {"status": "started", "job_id": job_id}
    
    return {"status": "unknown_intent"}

# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health(request: Request):
    """Quick liveness check. Returns device identity and optional build status."""
    active_build = None
    if context_repo := request.query_params.get("context_repo"):
        if "/" in context_repo:
            owner, repo = context_repo.split("/")
            active_build = await check_active_build(owner, repo)

    # Log the connection for visual feedback
    await agent_log(f"🔗 Mobile App Synced", "info", "system")
    
    return {
        "status": "ok", 
        "agent": "Antigravity Bridge", 
        "device": DEVICE_NAME,
        "active_build": active_build,
        "version": "0.1.0"
    }


@app.post("/command", response_model=JobStatus, tags=["Execution"], dependencies=[Depends(verify_token)])
async def run_command_endpoint(req: CommandRequest, background_tasks: BackgroundTasks):
    """
    Execute a shell command on the remote machine.

    - **sync** (`async_run=false`): Blocks until done, returns full result.
    - **async** (`async_run=true`): Returns a `job_id` immediately. Poll `/jobs/{job_id}` for the result.
    """
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "result": None}

    context_str = f" [{req.context_repo}]" if req.context_repo else ""
    
    if req.async_run:
        await agent_log(f"⏳ Queued async command{context_str}: {req.command[:30]}...")
        background_tasks.add_task(_run_command, job_id, req.command, req.context_repo)
        return JobStatus(job_id=job_id, status="queued")
    else:
        await agent_log(f"⚡ Running sync command{context_str}: {req.command[:30]}...")
        await _run_command(job_id, req.command, req.context_repo)
        return JobStatus(job_id=job_id, status=jobs[job_id]["status"], result=jobs[job_id]["result"])


@app.post("/intent", tags=["Execution"], dependencies=[Depends(verify_token)])
async def intent_endpoint(req: IntentRequest, background_tasks: BackgroundTasks):
    """Higher-level endpoint for spoken intents like 'update the site'."""
    context_str = f" ({req.context_repo})" if req.context_repo else ""
    await agent_log(f"🧠 Intent received: {req.intent}{context_str}")
    result = await handle_intent(req.intent, req.params or {}, background_tasks)
    if result["status"] == "unknown_intent":
        raise HTTPException(status_code=400, detail="Unknown intent.")
    return result

@app.post("/chat", tags=["AI"], dependencies=[Depends(verify_token)])
async def gemini_chat(req: ChatRequest):
    """Voice-to-Gemini chat scoped to a specific repository context and model."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=400, detail="GEMINI_API_KEY not configured on agent.")
    
    context_str = f" [Repo: {req.context_repo}]" if req.context_repo else ""
    await agent_log(f"🧠 Gemini Inquiry ({req.model_id}){context_str}: {req.message}")
    
    try:
        model = genai.GenerativeModel(req.model_id or 'gemini-1.5-flash')
        # AI prompt log
        await agent_log(f"Prompt: {req.message}", "info", "user")
        
        # Inject project context if available
        cwd = resolve_repo_path(req.context_repo)
        system_context = f"You are Antigravity, an AI developer assistant. You are currently helping the user with their project at: {cwd}. "
        
        response = model.generate_content(system_context + req.message)
        ai_response = response.text.strip()
        
        # Confirmation message with device identity
        await agent_log(ai_response, "success", "gemini")
        return {"response": ai_response, "device": DEVICE_NAME}
    except Exception as e:
        await agent_log(f"❌ Gemini Error: {str(e)}", "error")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/upload", tags=["Assets"], dependencies=[Depends(verify_token)])
async def upload_asset(
    request: Request,
    file: UploadFile = File(...),
    x_context_repo: Optional[str] = Header(None)
):
    """Receive an asset (image/file) and save it to the target repository directory."""
    try:
        # Resolve target directory using our new universal system
        cwd = resolve_repo_path(x_context_repo)
        
        # Assets always go into the 'assets' folder of the project
        dest_dir = os.path.join(cwd, "assets")
        os.makedirs(dest_dir, exist_ok=True)
        
        file_path = os.path.join(dest_dir, file.filename)
        
        with open(file_path, "wb") as f:
            f.write(await file.read())
            
        await agent_log(f"📁 Asset Received: {file.filename} -> {dest_dir}", "success")
        return {"status": "success", "path": file_path}
    except Exception as e:
        await agent_log(f"❌ Upload Error: {str(e)}", "error")
        raise HTTPException(status_code=500, detail=str(e))


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
    await agent_log(f"🔔 Manual Notification sent: {req.title}")
    await send_ding(req.title, req.body, req.token)
    return {"status": "sent"}


@app.post("/approve/{approval_id}", tags=["Notifications"], dependencies=[Depends(verify_token)])
async def approve_endpoint(approval_id: str, accept: bool):
    """Called by the mobile app to respond to a request_approval prompt."""
    if approval_id not in approvals:
        raise HTTPException(status_code=404, detail="Approval request expired or not found.")
    
    approvals[approval_id]["result"] = accept
    approvals[approval_id]["event"].set()
    return {"status": "success", "accepted": accept}


@app.get("/repos", tags=["GitHub"], dependencies=[Depends(verify_token)])
async def list_github_repos():
    """List all repos for the authenticated user across personal + org accounts."""
    if not GITHUB_TOKEN:
        raise HTTPException(status_code=400, detail="GITHUB_TOKEN not configured on agent.")

    gh_headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "AntigravityBridgeAgent"
    }

    async with httpx.AsyncClient() as client:
        try:
            # 1. Fetch personal repos
            await agent_log("📡 Fetching personal repositories...")
            personal_resp = await client.get(
                "https://api.github.com/user/repos?per_page=100&sort=updated&type=owner",
                headers=gh_headers
            )
            if personal_resp.status_code != 200:
                await agent_log(f"❌ GitHub Personal Repos failed: {personal_resp.status_code}", "error")
            personal_resp.raise_for_status()

            repos = []
            for r in personal_resp.json():
                repos.append(GitHubRepo(
                    id=r["id"],
                    name=r["name"],
                    full_name=r["full_name"],
                    owner=r["owner"]["login"],
                    is_org=False,
                    visibility=r.get("visibility", "private"),
                    description=r.get("description"),
                    url=r["html_url"],
                    updated_at=r.get("updated_at", ""),
                ))

            # 2. Fetch org repos
            await agent_log("📡 Fetching user organizations...")
            orgs_resp = await client.get("https://api.github.com/user/orgs?per_page=100", headers=gh_headers)
            if orgs_resp.status_code != 200:
                await agent_log(f"⚠️ GitHub Organizations failed: {orgs_resp.status_code} - {orgs_resp.text}", "warning")
            else:
                for org in orgs_resp.json():
                    org_login = org["login"]
                    await agent_log(f"📡 Fetching repos for org: {org_login}...")
                    org_repos_resp = await client.get(
                        f"https://api.github.com/orgs/{org_login}/repos?per_page=100&sort=updated",
                        headers=gh_headers
                    )
                    if org_repos_resp.status_code == 200:
                        for r in org_repos_resp.json():
                            repos.append(GitHubRepo(
                                id=r["id"],
                                name=r["name"],
                                full_name=r["full_name"],
                                owner=org_login,
                                is_org=True,
                                visibility=r.get("visibility", "private"),
                                description=r.get("description"),
                                url=r["html_url"],
                                updated_at=r.get("updated_at", ""),
                            ))
                    else:
                        await agent_log(f"⚠️ Failed to fetch repos for org {org_login}: {org_repos_resp.status_code}", "warning")

            sorted_repos = sorted(repos, key=lambda x: x.updated_at, reverse=True)
            await agent_log(f"✅ Found {len(sorted_repos)} total repositories.")
            return [r.dict() for r in sorted_repos]
        except httpx.HTTPStatusError as e:
            await agent_log(f"❌ GitHub API Error: {e.response.status_code} - {e.response.text}", "error")
            raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
        except Exception as e:
            await agent_log(f"❌ unexpected Error in /repos: {str(e)}", "error")
            raise HTTPException(status_code=500, detail=str(e))


@app.get("/workflows", tags=["GitHub"], dependencies=[Depends(verify_token)])
async def get_github_workflows(owner: str, repo: str):
    """Fetch recent workflow runs from GitHub for a specific repository."""
    if not GITHUB_TOKEN:
        raise HTTPException(status_code=400, detail="GITHUB_TOKEN not configured on agent.")

    gh_headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "AntigravityBridgeAgent"
    }

    async with httpx.AsyncClient() as client:
        try:
            # Get repo metadata for visibility
            repo_resp = await client.get(
                f"https://api.github.com/repos/{owner}/{repo}", headers=gh_headers
            )
            visibility = repo_resp.json().get("visibility", "public") if repo_resp.status_code == 200 else "public"

            # Get workflow runs
            runs_resp = await client.get(
                f"https://api.github.com/repos/{owner}/{repo}/actions/runs?per_page=10",
                headers=gh_headers
            )
            if runs_resp.status_code == 401:
                raise HTTPException(status_code=401, detail="GitHub Token is invalid or expired. Update .env.")
            runs_resp.raise_for_status()

            runs = []
            for run in runs_resp.json().get("workflow_runs", []):
                runs.append(WorkflowRun(
                    id=run["id"],
                    name=run["name"],
                    status=run["status"],
                    conclusion=run["conclusion"],
                    repo=f"{owner}/{repo}",
                    url=run["html_url"],
                    visibility=visibility,
                    created_at=run["created_at"]
                ))
            return runs
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=e.response.text)
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))


async def monitor_workflows_task():
    """Background task to poll GitHub for workflow completion and send Dings."""
    if not GITHUB_TOKEN or not firebase_admin._apps:
        return

    # This is a simplified poller. In a real app, you'd use webhooks or a more robust scheduler.
    GITHUB_OWNER = os.getenv("GITHUB_OWNER", "THEAMATEURSWAMI")
    GITHUB_REPO = os.getenv("GITHUB_REPO", "Gravity2Phone")

    while True:
        try:
            url = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/actions/runs?per_page=5"
            headers = {
                "Authorization": f"Bearer {GITHUB_TOKEN}",
                "Accept": "application/vnd.github.v3+json",
                "User-Agent": "AntigravityBridgeAgent"
            }
            
            async with httpx.AsyncClient() as client:
                resp = await client.get(url, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    for run in data.get("workflow_runs", []):
                        run_id = run["id"]
                        status = run["status"]
                        conclusion = run["conclusion"]
                        
                        # If it was running and now it's completed
                        if run_id in monitored_workflows and status == "completed":
                            last_status = monitored_workflows[run_id]
                            if last_status != "completed":
                                icon = "✅" if conclusion == "success" else "❌"
                                await send_ding(
                                    title=f"Workflow {icon}",
                                    body=f"{GITHUB_REPO}: {run['name']} finished with {conclusion}."
                                )
                                monitored_workflows[run_id] = "completed"
                        
                        # Track currently running ones
                        elif status != "completed":
                            monitored_workflows[run_id] = status

        except Exception as e:
            print(f"Error in workflow monitor: {e}")
            
        await asyncio.sleep(60) # Poll every minute


@app.on_event("startup")
async def startup_event():
    asyncio.create_task(monitor_workflows_task())


@app.get("/quota", tags=["System"], dependencies=[Depends(verify_token)])
async def get_model_quota():
    """Get current token usage and reset timers for AI models."""
    # In a real app, you'd fetch this from your LLM provider's headers or DB
    # For now, we return mock data for the UI
    now = datetime.now(timezone.utc)
    reset_time = now.replace(hour=now.hour + 1, minute=0, second=0, microsecond=0)
    
    return [
        ModelQuota(
            name="Claude 3.5 Sonnet",
            model_id="claude-3-5-sonnet",
            used_tokens=42500,
            total_tokens=200000,
            reset_at=reset_time.isoformat(),
            reset_seconds=int((reset_time - now).total_seconds())
        ),
        ModelQuota(
            name="GPT-4o",
            model_id="gpt-4o",
            used_tokens=8500,
            total_tokens=30000,
            reset_at=reset_time.isoformat(),
            reset_seconds=int((reset_time - now).total_seconds())
        )
    ]

@app.delete("/jobs/{job_id}", tags=["Execution"], dependencies=[Depends(verify_token)])
async def clear_job(job_id: str):
    """Remove a job from the store."""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found.")
    del jobs[job_id]
    return {"deleted": job_id}

@app.get("/logs", tags=["System"])
async def stream_logs(request: Request):
    """Real-time SSE stream of agent logs/chats (Broadcast to all listeners)."""
    queue = asyncio.Queue()
    
    # Pre-populate with history so the app session has context
    for entry in log_history:
        await queue.put(entry)
        
    log_listeners.append(queue)
    
    async def event_generator():
        try:
            while True:
                if await request.is_disconnected():
                    break
                
                log = await queue.get()
                yield {
                    "event": "log",
                    "data": json.dumps(log)
                }
        finally:
            # Clean up when client disconnects
            if queue in log_listeners:
                log_listeners.remove(queue)

    return EventSourceResponse(event_generator())

@app.get("/history", tags=["Discovery"], dependencies=[Depends(verify_token)])
async def get_cloud_history(limit: int = 50, offset: int = 0):
    """Fetch global log history from Firestore with pagination."""
    if not db:
        raise HTTPException(status_code=400, detail="Cloud storage not initialized.")
    
    try:
        query = db.collection("logs").order_by("server_timestamp", direction=firestore.Query.DESCENDING)
        
        # Note: True pagination in Firestore uses start_at/start_after for performance, 
        # but for this scale offset is fine.
        docs = query.offset(offset).limit(limit).stream()
        history = []
        for doc in docs:
            data = doc.to_dict()
            if "server_timestamp" in data and data["server_timestamp"]:
                data["server_timestamp"] = data["server_timestamp"].isoformat()
            history.append(data)
            
        return history[::-1]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    host = os.getenv("AGENT_HOST", "0.0.0.0")
    port = int(os.getenv("AGENT_PORT", "8742"))
    uvicorn.run(app, host=host, port=port)
