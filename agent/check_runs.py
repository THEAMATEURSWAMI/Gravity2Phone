import httpx
import os

token = os.getenv("GITHUB_TOKEN")
if not token:
    print("GITHUB_TOKEN not set in environment.")
    exit(1)
headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github.v3+json"
}

resp = httpx.get("https://api.github.com/repos/THEAMATEURSWAMI/Gravity2Phone/actions/runs?per_page=5", headers=headers)
runs = resp.json().get("workflow_runs", [])
for r in runs:
    print(f"{r['id']} - {r['status']} - {r['conclusion']} - {r['head_commit']['message']}")
