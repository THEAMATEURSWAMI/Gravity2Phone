# Antigravity Bridge — Session Overview

> **Last updated:** 2026-02-23  
> **Status:** 🟢 Agent Running | 📱 App Distributed

---

## What This Is

**Antigravity Bridge** is a voice-controlled mobile command center that connects your phone to your development machine over your local network or Tailscale VPN.

- **Agent** (`agent/`) — A Python FastAPI server that runs on your PC
- **App** (`app/`) — A Flutter Android app distributed via Firebase App Distribution

---

## Architecture

```
Phone (Flutter App)
    │  HTTP over Wi-Fi or Tailscale VPN
    ▼
Agent (FastAPI @ :8742)
    │
    ├── Execute shell commands (sync or background)
    ├── Trigger intents ("update-site" → git pull → build → deploy)
    ├── Monitor GitHub workflow runs → send push notifications (Dings)
    ├── Interactive approval prompts (yes/no dialog on phone)
    └── Browse GitHub repos across personal + org accounts
```

---

## Current Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness check (no auth required) |
| `POST` | `/command` | Execute a shell command (sync or async) |
| `POST` | `/intent` | Trigger a named workflow (e.g. `update-site`) |
| `GET` | `/repos` | List all GitHub repos (personal + orgs) with visibility |
| `GET` | `/workflows?owner=&repo=` | Fetch recent workflow runs for a repo |
| `POST` | `/notify` | Send a manual push notification (Ding) |
| `POST` | `/approve/{id}` | Respond to an interactive approval prompt |
| `GET` | `/jobs/{id}` | Poll an async background job |

---

## App Navigation

```
Home Screen (Hold to Speak)
    ├── 🚀 Rocket icon → Workflows Screen
    │       ├── Tab 1: Repos  — browse personal + org repos, tap to view runs
    │       └── Tab 2: Runs   — workflow status with progress bar + visibility badge
    └── ⚙️ Settings icon → Agent URL + Token config
```

---

## Mobile App Features

- **Hold-to-speak** voice commands → dispatched to agent
- **Intent recognition** — phrases like "update the site" trigger complex multi-step workflows  
- **Approval dialogs** — critical commands pause and wait for your tap (Accept / Reject)
- **GitHub Workflows** — browse all repos (personal + org), see if they're public/private, and watch live run progress
- **Push Notifications (Dings)** — Firebase Cloud Messaging delivers background alerts when builds finish

---

## Configuration

**`agent/.env`**
```
API_SECRET_TOKEN=your_bridge_secret_here
GITHUB_TOKEN=<your_PAT>
GITHUB_OWNER=your_github_username
GITHUB_REPO=your_repo_name
AGENT_HOST=0.0.0.0
AGENT_PORT=8742
FIREBASE_SERVICE_ACCOUNT_PATH=service-account.json
```

**App Settings** (set in-app)
```
Agent URL:  http://192.168.1.x:8742   (local Wi-Fi)
            http://100.x.x.x:8742       (Tailscale)
Token:      your_bridge_secret_here
```

---

## Running the Agent

```powershell
cd agent
python -m uvicorn main:app --host 0.0.0.0 --port 8742
```

---

## Deploying the App

```powershell
cd app
flutter build apk --debug
firebase appdistribution:distribute build\app\outputs\flutter-apk\app-debug.apk `
  --app <your_firebase_app_id> `
  --testers "your@email.com"
```

---

## Known Setup Notes

- **Tailscale** must be running on BOTH your phone and PC for the `100.x.x.x` address to work
- If Tailscale isn't active, use the local Wi-Fi IP (e.g. 192.168.1.x) while on the same network
- The `GITHUB_TOKEN` must have `repo` and `workflow` scopes to read private repos and workflow runs
- Firebase Cloud Messaging requires the app to be installed with notification permissions granted

---

## Roadmap

- [ ] Add `GITHUB_TOKEN` to the in-app Settings screen (avoid editing `.env` on PC)
- [ ] Support multiple monitored repos for background Dings  
- [ ] Diff-preview before deployment (send code changes to phone for review)
- [ ] Webhook-based workflow events instead of polling
- [ ] iPad / iOS support
