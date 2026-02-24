#!/usr/bin/env python3
"""
Antigravity Bridge - CLI Test Client
=====================================
A simple command-line tool to test your Remote Agent from the same machine
before the Flutter app is ready.

Usage:
  # Run a quick health check:
  python test_client.py health

  # Execute a command (sync):
  python test_client.py run "git status"

  # Execute a command async (get job ID, then poll):
  python test_client.py run "sleep 5 && echo done" --async

  # Check a job:
  python test_client.py job <job_id>
"""

import sys
import json
import argparse
import os
import urllib.request
import urllib.error

BASE_URL = os.getenv("AGENT_URL", "http://localhost:8742")
TOKEN = os.getenv("API_SECRET_TOKEN", "")


def headers():
    return {"X-API-Token": TOKEN, "Content-Type": "application/json"}


def get(path: str):
    req = urllib.request.Request(f"{BASE_URL}{path}", headers=headers())
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def post(path: str, body: dict):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(f"{BASE_URL}{path}", data=data, headers=headers(), method="POST")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def print_json(obj: dict):
    print(json.dumps(obj, indent=2))


def cmd_health(_args):
    print_json(get("/health"))


def cmd_run(args):
    body = {"command": args.command, "async_run": args.background}
    result = post("/command", body)
    print_json(result)


def cmd_job(args):
    print_json(get(f"/jobs/{args.job_id}"))


def cmd_jobs(_args):
    print_json(get("/jobs"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Antigravity Bridge Test Client")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("health", help="Ping the agent").set_defaults(func=cmd_health)
    sub.add_parser("jobs", help="List all jobs").set_defaults(func=cmd_jobs)

    p_run = sub.add_parser("run", help="Execute a shell command")
    p_run.add_argument("command", help="Shell command to run")
    p_run.add_argument("--async", dest="background", action="store_true", help="Run in background")
    p_run.set_defaults(func=cmd_run)

    p_job = sub.add_parser("job", help="Get status of a job")
    p_job.add_argument("job_id")
    p_job.set_defaults(func=cmd_job)

    args = parser.parse_args()

    if not TOKEN:
        print("⚠  Set API_SECRET_TOKEN in your environment before using this client.")
        sys.exit(1)

    try:
        args.func(args)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"HTTP {e.code}: {body}")
        sys.exit(1)
    except Exception as exc:
        print(f"Error: {exc}")
        sys.exit(1)
