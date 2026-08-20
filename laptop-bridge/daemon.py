"""RecTrace Laptop Bridge Daemon & Developer Cockpit.

Monitors an inbox folder for incoming .patch files, applies them to mock_project
using git, runs the pytest CI/CD suite, and serves real-time status and an interactive
web dashboard over FastAPI.
"""

import collections
import datetime
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

# Directory configurations
BASE_DIR = Path(__file__).resolve().parent
INBOX_DIR = BASE_DIR / "inbox_patches"
MOCK_PROJECT_DIR = BASE_DIR / "mock_project"
ROOT_INBOX_DIR = BASE_DIR.parent / "inbox_patches"

# Rolling history of the last 15 applied patches
MAX_HISTORY_LEN = 15
patch_history: collections.deque = collections.deque(maxlen=MAX_HISTORY_LEN)
processed_patches: set = set()
history_lock = threading.Lock()
DAEMON_START_TIME = datetime.datetime.now(datetime.timezone.utc)

BASELINE_APP_CODE = """\"\"\"Mock application module with an intentional baseline bug for PatchPilot verification.\"\"\"


def process_user_data(user_dict: dict) -> dict:
    \"\"\"Process user profile dictionary.

    Baseline BUG: Direct indexing causes KeyError when 'role' is missing in user_dict.
    \"\"\"
    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}


def get_user_role(user: dict) -> str:
    \"\"\"Retrieve user role.\"\"\"
    data = process_user_data(user)
    return data['role'].lower()


def format_user_badge(user: dict) -> str:
    \"\"\"Format user badge display string.\"\"\"
    name = user.get("name", "Anonymous")
    data = process_user_data(user)
    return f"[{data['role']}] {name}"
"""

# FastAPI application
app = FastAPI(
    title="RecTrace Laptop Bridge",
    description="Automated git patch runner and CI/CD verification bridge",
    version="1.1.0",
)

# Enable CORS for cross-origin browser dashboards and mobile emulators/devices
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_git_command() -> str:
    """Resolve git executable path across environments."""
    git_bin = shutil.which("git")
    if git_bin:
        return git_bin
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Git" / "cmd" / "git.exe",
        Path("C:/Program Files/Git/cmd/git.exe"),
        Path("C:/Program Files/Git/bin/git.exe"),
        Path("C:/Program Files (x86)/Git/cmd/git.exe"),
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return "git"


def run_cmd(cmd, cwd=None, check=True):
    """Run command and return CompletedProcess."""
    result = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(cmd) if isinstance(cmd, list) else cmd}\n"
            f"Exit Code: {result.returncode}\n"
            f"Stdout: {result.stdout}\n"
            f"Stderr: {result.stderr}"
        )
    return result


def get_local_ip_addresses() -> List[str]:
    """Discover host machine local IPv4 addresses."""
    ips = ["127.0.0.1"]
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            ip = info[4][0]
            if ":" not in ip and ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    return ips


def execute_test_suite() -> Dict[str, Any]:
    """Execute pytest suite on mock_project."""
    try:
        res = subprocess.run(
            [sys.executable, "-m", "pytest", str(MOCK_PROJECT_DIR)],
            capture_output=True,
            text=True,
            check=False,
        )
        combined_output = (res.stdout + "\n" + res.stderr).strip()
        status = "PASSED" if res.returncode == 0 else "FAILED"
        return {"status": status, "output": combined_output, "exit_code": res.returncode}
    except Exception as e:
        return {"status": "ERROR", "output": str(e), "exit_code": -1}


def apply_unified_diff_fallback(patch_path: Path, project_dir: Path) -> Tuple[bool, str]:
    """Fuzzy/direct fallback patch applicator when standard `git apply` fails.
    Extracts target file, removed lines, and replacement lines from unified diff.
    """
    try:
        patch_text = patch_path.read_text(encoding="utf-8", errors="replace")
        lines = patch_text.replace("\r\n", "\n").split("\n")

        # 1. Identify target file
        target_file = None
        for line in lines:
            if line.startswith("+++ b/") or line.startswith("+++ "):
                target_file = line.replace("+++ b/", "").replace("+++ ", "").strip()
                break
            elif line.startswith("--- a/") or line.startswith("--- "):
                target_file = line.replace("--- a/", "").replace("--- ", "").strip()
                break

        if not target_file:
            target_file = "app.py"

        target_path = project_dir / target_file
        if not target_path.exists():
            found = list(project_dir.glob(f"**/{Path(target_file).name}"))
            if found:
                target_path = found[0]
            else:
                return False, f"Target file {target_file} not found in {project_dir}"

        content = target_path.read_text(encoding="utf-8", errors="replace")

        # Extract deleted and added blocks from hunks
        hunks = re.split(r"^@@\s+-\d+(?:,\d+)?\s+\+\d+(?:,\d+)?\s+@@", patch_text, flags=re.MULTILINE)

        modified = False
        for hunk in hunks[1:] if len(hunks) > 1 else [patch_text]:
            deleted_lines = []
            added_lines = []
            for hline in hunk.split("\n"):
                if hline.startswith("-") and not hline.startswith("---"):
                    deleted_lines.append(hline[1:])
                elif hline.startswith("+") and not hline.startswith("+++"):
                    added_lines.append(hline[1:])

            if deleted_lines:
                target_block = "\n".join(deleted_lines)
                replacement_block = "\n".join(added_lines)

                if target_block in content:
                    content = content.replace(target_block, replacement_block, 1)
                    modified = True
                else:
                    target_block_clean = target_block.strip()
                    replacement_block_clean = replacement_block.strip()
                    if target_block_clean in content:
                        content = content.replace(target_block_clean, replacement_block_clean, 1)
                        modified = True
                    else:
                        for del_l, add_l in zip(deleted_lines, added_lines):
                            if del_l.strip() in content:
                                content = content.replace(del_l.strip(), add_l.strip(), 1)
                                modified = True

        if modified:
            target_path.write_text(content, encoding="utf-8")
            return True, f"Successfully applied fallback AST/diff patch to {target_path.name}"
        return False, "Could not match target diff lines in source file"
    except Exception as e:
        return False, f"Fallback diff parsing error: {e}"


def execute_patch_pipeline(patch_path: Path) -> Dict[str, Any]:
    """Apply a git patch to mock_project and run pytest verification."""
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    patch_name = patch_path.name
    print(f"\n[+] Processing incoming patch: {patch_name}")

    record: Dict[str, Any] = {
        "patch_file": patch_name,
        "timestamp": timestamp,
        "git_apply_status": "FAILED",
        "git_apply_output": "",
        "test_status": "SKIPPED",
        "test_output": "",
        "build_status": "FAILED",
    }

    # Step 1: Execute git apply with fallback support
    try:
        git_bin = get_git_command()
        git_cmd = [git_bin, "-C", str(MOCK_PROJECT_DIR), "apply", "--ignore-whitespace", str(patch_path.resolve())]
        git_result = subprocess.run(
            git_cmd,
            capture_output=True,
            text=True,
            check=False,
        )
        record["git_apply_output"] = (git_result.stdout + "\n" + git_result.stderr).strip()

        if git_result.returncode != 0:
            # Attempt fallback AST/diff patcher
            fallback_ok, fallback_msg = apply_unified_diff_fallback(patch_path, MOCK_PROJECT_DIR)
            if fallback_ok:
                record["git_apply_status"] = "SUCCESS"
                record["git_apply_output"] = f"[Fallback Diff Applier] {fallback_msg}"
                print(f"[✓] Fallback patch applied successfully: {patch_name}")
            else:
                record["git_apply_status"] = "FAILED"
                record["build_status"] = "GIT APPLY FAILED"
                print(f"[✗] GIT APPLY FAILED for {patch_name}: {record['git_apply_output']} | {fallback_msg}")
                with history_lock:
                    patch_history.append(record)
                return record
        else:
            record["git_apply_status"] = "SUCCESS"
            print(f"[✓] Git patch applied successfully: {patch_name}")
    except Exception as e:
        fallback_ok, fallback_msg = apply_unified_diff_fallback(patch_path, MOCK_PROJECT_DIR)
        if fallback_ok:
            record["git_apply_status"] = "SUCCESS"
            record["git_apply_output"] = f"[Fallback Diff Applier] {fallback_msg}"
            print(f"[✓] Fallback patch applied successfully: {patch_name}")
        else:
            record["git_apply_status"] = "ERROR"
            record["git_apply_output"] = str(e)
            record["build_status"] = "GIT APPLY ERROR"
            print(f"[✗] Error executing git apply: {e}")
            with history_lock:
                patch_history.append(record)
            return record

    # Step 2: Run pytest suite on mock_project
    test_res = execute_test_suite()
    record["test_output"] = test_res["output"]

    # Step 3: Log verification results
    if test_res["status"] == "PASSED":
        record["test_status"] = "PASSED"
        record["build_status"] = "BUILD PASSING"
        print(f"[✓] BUILD PASSING - Tests passed for patch {patch_name}")
    else:
        record["test_status"] = "FAILED"
        record["build_status"] = "BUILD FAILED"
        print(f"[✗] BUILD FAILED - Tests failed for patch {patch_name}")

    with history_lock:
        patch_history.append(record)

    return record


def reset_testbed_state() -> Dict[str, Any]:
    """Re-initialize mock_project to the intentional baseline bug state."""
    app_file = MOCK_PROJECT_DIR / "app.py"
    app_file.write_text(BASELINE_APP_CODE, encoding="utf-8")

    git_bin = get_git_command()
    git_dir = MOCK_PROJECT_DIR / ".git"

    if git_dir.exists():
        try:
            subprocess.run([git_bin, "-C", str(MOCK_PROJECT_DIR), "checkout", "-B", "main"], check=False, capture_output=True)
            subprocess.run([git_bin, "-C", str(MOCK_PROJECT_DIR), "reset", "--hard", "HEAD"], check=False, capture_output=True)
            subprocess.run([git_bin, "-C", str(MOCK_PROJECT_DIR), "clean", "-fd"], check=False, capture_output=True)
            app_file.write_text(BASELINE_APP_CODE, encoding="utf-8")
        except Exception:
            pass

    # Run tests to confirm baseline failure
    test_res = execute_test_suite()
    return {
        "status": "baseline_reset",
        "message": "Mock project reset to baseline bug state (KeyError on missing 'role').",
        "test_status": test_res["status"],
        "test_output": test_res["output"],
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


# ==============================================================================
# FastAPI Routes & Real-time Web Cockpit
# ==============================================================================


@app.get("/", response_class=HTMLResponse)
def index_or_root(request: Request):
    """Serve rich Developer Cockpit HTML or JSON based on Accept header."""
    accept = request.headers.get("accept", "")
    if "text/html" not in accept and "application/json" in accept:
        return JSONResponse(
            content={
                "service": "RecTrace Laptop Bridge",
                "status": "online",
                "inbox_directory": str(INBOX_DIR),
                "mock_project_directory": str(MOCK_PROJECT_DIR),
                "ips": get_local_ip_addresses(),
            }
        )

    with history_lock:
        history_list = list(patch_history)
        last_rec = history_list[-1] if history_list else None

    # Build HTML Dashboard
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>RecTrace • Laptop Bridge Cockpit</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #09090B;
      --card-bg: #121215;
      --card-border: #27272A;
      --text: #F4F4F5;
      --text-muted: #A1A1AA;
      --emerald: #10B981;
      --emerald-glow: rgba(16, 185, 129, 0.2);
      --red: #EF4444;
      --red-glow: rgba(239, 68, 68, 0.2);
      --amber: #F59E0B;
      --accent: #3B82F6;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: var(--bg);
      color: var(--text);
      font-family: 'Inter', -apple-system, sans-serif;
      min-height: 100vh;
      padding: 32px 20px;
    }}
    .container {{
      max-width: 1080px;
      margin: 0 auto;
    }}
    header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 28px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--card-border);
    }}
    .brand {{
      display: flex;
      align-items: center;
      gap: 12px;
    }}
    .logo-badge {{
      background: #000000;
      border: 1px solid #27272A;
      width: 38px;
      height: 38px;
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 16px rgba(255, 255, 255, 0.08);
    }}
    h1 {{
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.5px;
    }}
    .subtitle {{
      font-size: 12px;
      color: var(--text-muted);
    }}
    .header-actions {{
      display: flex;
      gap: 10px;
      align-items: center;
    }}
    .btn {{
      background: #18181B;
      border: 1px solid var(--card-border);
      color: var(--text);
      padding: 8px 16px;
      border-radius: 9999px;
      font-size: 12px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s ease;
      text-decoration: none;
    }}
    .btn:hover {{
      background: #27272A;
      border-color: #3F3F46;
    }}
    .btn-primary {{
      background: #FAFAFA;
      color: #09090B;
      border: none;
    }}
    .btn-primary:hover {{
      background: #E4E4E7;
    }}
    .grid {{
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 20px;
      margin-bottom: 24px;
    }}
    @media (max-width: 800px) {{
      .grid {{ grid-template-columns: 1fr; }}
      header {{ flex-direction: column; align-items: flex-start; gap: 16px; }}
    }}
    .card {{
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 18px;
      padding: 20px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
    }}
    .card-header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
    }}
    .card-title {{
      font-size: 13px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
    }}
    .status-badge {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 9999px;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: -0.2px;
    }}
    .status-passing {{
      background: rgba(16, 185, 129, 0.15);
      color: #34D399;
      border: 1px solid rgba(16, 185, 129, 0.3);
      box-shadow: 0 0 16px var(--emerald-glow);
    }}
    .status-failed {{
      background: rgba(239, 68, 68, 0.15);
      color: #F87171;
      border: 1px solid rgba(239, 68, 68, 0.3);
      box-shadow: 0 0 16px var(--red-glow);
    }}
    .status-idle {{
      background: rgba(245, 158, 11, 0.15);
      color: #FBBF24;
      border: 1px solid rgba(245, 158, 11, 0.3);
    }}
    .dot {{
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: currentColor;
    }}
    .terminal-box {{
      background: #000;
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 14px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11.5px;
      color: #D4D4D8;
      max-height: 280px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
      line-height: 1.45;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
      text-align: left;
    }}
    th {{
      color: var(--text-muted);
      font-weight: 600;
      padding: 10px 12px;
      border-bottom: 1px solid var(--card-border);
    }}
    td {{
      padding: 12px;
      border-bottom: 1px solid rgba(39, 39, 42, 0.6);
      font-family: 'JetBrains Mono', monospace;
      font-size: 11.5px;
    }}
    .tag {{
      display: inline-block;
      padding: 2px 8px;
      border-radius: 6px;
      font-weight: 600;
      font-size: 10px;
    }}
    .tag-success {{ background: rgba(16, 185, 129, 0.2); color: #34D399; }}
    .tag-failed {{ background: rgba(239, 68, 68, 0.2); color: #F87171; }}
    .tag-skipped {{ background: rgba(161, 161, 170, 0.2); color: #A1A1AA; }}
    .network-pill {{
      display: flex;
      align-items: center;
      gap: 6px;
      background: #18181B;
      padding: 6px 12px;
      border-radius: 8px;
      border: 1px solid var(--card-border);
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      margin-top: 6px;
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <div class="logo-badge">
          <svg viewBox="0 0 512 512" width="24" height="24" fill="none">
            <path d="M 118 256 A 140 140 0 1 1 394 256" stroke="#FFFFFF" stroke-width="26" stroke-linecap="round"/>
            <path d="M 394 256 A 140 140 0 0 1 118 256" stroke="#FFFFFF" stroke-width="26" stroke-linecap="round"/>
            <line x1="280" y1="240" x2="330" y2="295" stroke="#FFFFFF" stroke-width="22" stroke-linecap="round"/>
            <circle cx="330" cy="295" r="26" fill="#FFFFFF"/>
            <polygon points="256,98 184,266 260,266 182,422 344,228 266,228 338,98" stroke="#FFFFFF" stroke-width="26" stroke-linejoin="miter"/>
          </svg>
        </div>
        <div>
          <h1>RecTrace Laptop Bridge</h1>
          <div class="subtitle">Real-Time Git Watcher & Pytest CI/CD Engine</div>
        </div>
      </div>
      <div class="header-actions">
        <button class="btn" onclick="resetTestbed()">🔄 Reset Testbed</button>
        <button class="btn" onclick="runTests()">🧪 Run Tests</button>
        <button class="btn btn-primary" onclick="location.reload()">Refresh</button>
      </div>
    </header>

    <div class="grid">
      <!-- Left Column: CI/CD Build Status -->
      <div class="card">
        <div class="card-header">
          <div class="card-title">Live Build Verification Status</div>
          <div id="build-status-badge">
            {"<div class='status-badge status-passing'><span class='dot'></span>BUILD PASSING</div>" if last_rec and last_rec.get("build_status") == "BUILD PASSING" else ("<div class='status-badge status-failed'><span class='dot'></span>" + last_rec.get("build_status", "BUILD FAILED") + "</div>" if last_rec else "<div class='status-badge status-idle'><span class='dot'></span>IDLE • LISTENING</div>")}
          </div>
        </div>

        <div style="margin-bottom: 12px; font-size: 12px; color: var(--text-muted);">
          Latest Verification Output:
        </div>
        <div class="terminal-box" id="latest-log">{last_rec.get("test_output") if last_rec and last_rec.get("test_output") else (last_rec.get("git_apply_output") if last_rec else "Waiting for incoming patches in inbox_patches/...")}</div>
      </div>

      <!-- Right Column: Host & Bridge Info -->
      <div class="card">
        <div class="card-header">
          <div class="card-title">Bridge Configuration</div>
        </div>
        <div style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
          Available Local IPs for Mobile Connection:
        </div>
        {"".join([f'<div class="network-pill"><span style="color:var(--emerald);">●</span> {ip}:8000</div>' for ip in get_local_ip_addresses()])}
        <div style="margin-top: 16px; font-size: 11px; color: var(--text-muted); line-height: 1.5;">
          • <strong>Android Emulator:</strong> Use <code>10.0.2.2:8000</code><br>
          • <strong>Local Host:</strong> Use <code>127.0.0.1:8000</code><br>
          • <strong>Physical Phone:</strong> Use Wi-Fi LAN IP above
        </div>
      </div>
    </div>

    <!-- Recent Patch History Table -->
    <div class="card">
      <div class="card-header">
        <div class="card-title">Recent Ingested Patches ({len(history_list)})</div>
      </div>
      <table>
        <thead>
          <tr>
            <th>Timestamp</th>
            <th>Patch File</th>
            <th>Git Apply</th>
            <th>Pytest Suite</th>
            <th>Build Status</th>
          </tr>
        </thead>
        <tbody id="patch-rows">
          {"".join([f'''<tr>
            <td style="color:var(--text-muted);">{r.get("timestamp", "")[-8:]}</td>
            <td style="color:#FFF; font-weight:600;">{r.get("patch_file", "")}</td>
            <td><span class="tag tag-{'success' if r.get('git_apply_status') == 'SUCCESS' else 'failed'}">{r.get('git_apply_status')}</span></td>
            <td><span class="tag tag-{'success' if r.get('test_status') == 'PASSED' else ('failed' if r.get('test_status') == 'FAILED' else 'skipped')}">{r.get('test_status')}</span></td>
            <td><strong style="color:{'#34D399' if r.get('build_status') == 'BUILD PASSING' else '#F87171'}">{r.get('build_status')}</strong></td>
          </tr>''' for r in reversed(history_list)]) if history_list else '<tr><td colspan="5" style="text-align:center; color:var(--text-muted); padding:24px;">No patches applied yet. Push a patch from the mobile app or drop a .patch file into inbox_patches/.</td></tr>'}
        </tbody>
      </table>
    </div>
  </div>

  <script>
    async function resetTestbed() {{
      const btn = event.target;
      btn.innerText = 'Resetting...';
      try {{
        const res = await fetch('/reset-testbed', {{ method: 'POST' }});
        const data = await res.json();
        alert(data.message);
        location.reload();
      }} catch (e) {{
        alert('Reset error: ' + e);
      }} finally {{
        btn.innerText = '🔄 Reset Testbed';
      }}
    }}

    async function runTests() {{
      const btn = event.target;
      btn.innerText = 'Running...';
      try {{
        const res = await fetch('/run-tests', {{ method: 'POST' }});
        const data = await res.json();
        document.getElementById('latest-log').innerText = data.output;
        alert('Test Run ' + data.status + ' (Exit Code: ' + data.exit_code + ')');
      }} catch (e) {{
        alert('Test execution error: ' + e);
      }} finally {{
        btn.innerText = '🧪 Run Tests';
      }}
    }}
  </script>
</body>
</html>"""
    return HTMLResponse(content=html)


@app.get("/health")
def health():
    """Health check endpoint with server timestamp and uptime."""
    now = datetime.datetime.now(datetime.timezone.utc)
    uptime_sec = (now - DAEMON_START_TIME).total_seconds()
    return {
        "status": "healthy",
        "timestamp": now.isoformat(),
        "uptime_seconds": round(uptime_sec, 2),
        "service": "RecTrace Laptop Bridge",
    }


@app.get("/status")
def get_status() -> Dict[str, Any]:
    """Return the last applied patches, test results, and daemon telemetry."""
    with history_lock:
        history_list = list(patch_history)
        last_result = history_list[-1] if history_list else None
    return {
        "total_patches_recorded": len(history_list),
        "last_result": last_result,
        "recent_patches": history_list,
        "ips": get_local_ip_addresses(),
        "inbox_directory": str(INBOX_DIR),
        "mock_project_directory": str(MOCK_PROJECT_DIR),
    }


@app.get("/repo-files")
def get_repo_files_endpoint() -> Dict[str, Any]:
    """List source code files in the active workspace."""
    allowed_exts = {".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".java", ".rs", ".dart", ".json", ".yaml", ".yml"}
    files = []
    for p in MOCK_PROJECT_DIR.rglob("*"):
        if p.is_file() and not any(part.startswith(".") or part == "__pycache__" for part in p.parts):
            if p.suffix.lower() in allowed_exts:
                rel_path = p.relative_to(MOCK_PROJECT_DIR).as_posix()
                files.append({
                    "path": rel_path,
                    "filename": p.name,
                    "size": p.stat().st_size,
                })
    return {"files": files, "workspace": str(MOCK_PROJECT_DIR)}


@app.get("/file-content")
def get_file_content_endpoint(path: str) -> Dict[str, Any]:
    """Return raw content of a file in the active workspace."""
    target = (MOCK_PROJECT_DIR / path).resolve()
    if not str(target).startswith(str(MOCK_PROJECT_DIR.resolve())):
        return JSONResponse(status_code=403, content={"error": "Access denied"})
    if not target.exists() or not target.is_file():
        return JSONResponse(status_code=404, content={"error": "File not found"})

    content = target.read_text(encoding="utf-8", errors="replace")
    return {
        "path": path,
        "filename": target.name,
        "content": content,
        "lines": len(content.splitlines()),
    }


@app.post("/reset-testbed")
def reset_testbed_endpoint() -> Dict[str, Any]:
    """Reset mock_project to the intentional baseline bug state."""
    return reset_testbed_state()


@app.post("/run-tests")
def run_tests_endpoint() -> Dict[str, Any]:
    """Execute pytest suite on demand on mock_project."""
    return execute_test_suite()


class BranchCommitPayload(BaseModel):
    branch_name: Optional[str] = None
    commit_message: Optional[str] = None
    patch_file: Optional[str] = None


def get_git_info() -> Dict[str, Any]:
    """Retrieve current git branch and latest commit info from mock_project."""
    git_bin = get_git_command()
    try:
        branch_res = subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        current_branch = branch_res.stdout.strip() if branch_res.returncode == 0 else "main"

        sha_res = subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        latest_sha = sha_res.stdout.strip() if sha_res.returncode == 0 else "initial"

        msg_res = subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "log", "-1", "--pretty=%B"],
            capture_output=True,
            text=True,
            check=False,
        )
        latest_msg = msg_res.stdout.strip() if msg_res.returncode == 0 else ""

        return {
            "current_branch": current_branch,
            "latest_commit_sha": latest_sha,
            "latest_commit_message": latest_msg,
        }
    except Exception as e:
        return {
            "current_branch": "main",
            "latest_commit_sha": "unknown",
            "latest_commit_message": str(e),
        }


def create_git_branch_and_commit(
    branch_name: Optional[str] = None,
    commit_message: Optional[str] = None,
    patch_file: Optional[str] = None,
) -> Dict[str, Any]:
    """Create a new git branch and commit the current changes in mock_project."""
    git_bin = get_git_command()
    timestamp_slug = datetime.datetime.now(datetime.timezone.utc).strftime("%m%d-%H%M%S")

    if not branch_name or not branch_name.strip():
        prefix = patch_file.replace(".patch", "").replace("fix_", "") if patch_file else "bugfix"
        branch_name = f"rectrace/fix-{prefix}-{timestamp_slug}"
    else:
        branch_name = branch_name.strip().replace(" ", "-")

    if not commit_message or not commit_message.strip():
        commit_message = f"fix: auto-remediated by RecTrace [{branch_name}]"
    else:
        commit_message = commit_message.strip()

    try:
        # Check out or switch to the new branch
        subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "checkout", "-B", branch_name],
            capture_output=True,
            text=True,
            check=False,
        )

        # Stage all modifications in mock_project
        subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "add", "-A"],
            capture_output=True,
            text=True,
            check=False,
        )

        # Commit changes
        commit_res = subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "commit", "-m", commit_message],
            capture_output=True,
            text=True,
            check=False,
        )

        # Get latest commit SHA
        sha_res = subprocess.run(
            [git_bin, "-C", str(MOCK_PROJECT_DIR), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        commit_sha = sha_res.stdout.strip() if sha_res.returncode == 0 else "unknown"

        print(f"[✓] Created Git branch '{branch_name}' (Commit SHA: {commit_sha})")
        return {
            "status": "success",
            "branch": branch_name,
            "commit_sha": commit_sha,
            "commit_message": commit_message,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "message": f"Created branch '{branch_name}' and committed changes (SHA: {commit_sha})",
        }
    except Exception as e:
        print(f"[✗] Error creating branch/commit: {e}")
        return {
            "status": "error",
            "message": f"Git branch/commit error: {e}",
            "branch": branch_name,
            "commit_sha": None,
        }


@app.get("/git-info")
def git_info_endpoint() -> Dict[str, Any]:
    """Return current git branch and commit information."""
    return get_git_info()


@app.post("/create-branch-commit")
def create_branch_commit_endpoint(payload: BranchCommitPayload) -> Dict[str, Any]:
    """Create a new git branch and commit applied patch changes."""
    return create_git_branch_and_commit(
        branch_name=payload.branch_name,
        commit_message=payload.commit_message,
        patch_file=payload.patch_file,
    )


class PatchPayload(BaseModel):
    filename: Optional[str] = "fix.patch"
    patch: str


@app.post("/apply-patch")
def apply_patch_endpoint(payload: PatchPayload) -> Dict[str, Any]:
    """Receive git patch via HTTP, write to inbox, and run CI/CD pipeline."""
    fname = payload.filename or "fix.patch"
    if not fname.endswith(".patch"):
        fname = f"{fname}.patch"

    patch_path = INBOX_DIR / fname
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    patch_path.write_text(payload.patch, encoding="utf-8")

    # Mark as processed to prevent double execution if watchdog is active
    try:
        stat = patch_path.stat()
        processed_patches.add((str(patch_path.resolve()), stat.st_mtime, stat.st_size))
    except Exception:
        pass

    record = execute_patch_pipeline(patch_path)
    return {
        "status": "success" if record["build_status"] == "BUILD PASSING" else "failed",
        "record": record,
        "message": f"Patch {fname} processed. Build status: {record['build_status']}",
    }


class PatchInboxHandler(FileSystemEventHandler):
    """Watches for new .patch files in the inbox directory."""

    def on_created(self, event: FileSystemEvent):
        if event.is_directory:
            return
        self._handle_file(Path(event.src_path))

    def on_modified(self, event: FileSystemEvent):
        if event.is_directory:
            return
        self._handle_file(Path(event.src_path))

    def _handle_file(self, file_path: Path):
        if file_path.suffix.lower() != ".patch":
            return

        resolved_path = file_path.resolve()
        # Brief pause to ensure writing process finishes flushing to disk
        time.sleep(0.25)

        if not resolved_path.exists():
            return

        try:
            stat = resolved_path.stat()
            file_key = (str(resolved_path), stat.st_mtime, stat.st_size)
            if file_key in processed_patches or stat.st_size == 0:
                return
            processed_patches.add(file_key)
        except Exception:
            return

        execute_patch_pipeline(resolved_path)


def start_watcher(inbox_dir: Path) -> Observer:
    """Start watchdog observer on inbox directory and repo root inbox."""
    inbox_dir.mkdir(parents=True, exist_ok=True)
    event_handler = PatchInboxHandler()
    observer = Observer()
    observer.schedule(event_handler, path=str(inbox_dir), recursive=False)

    if ROOT_INBOX_DIR.resolve() != inbox_dir.resolve():
        ROOT_INBOX_DIR.mkdir(parents=True, exist_ok=True)
        observer.schedule(event_handler, path=str(ROOT_INBOX_DIR), recursive=False)
        print(f"[*] RecTrace File Watcher listening on: {ROOT_INBOX_DIR}")

    observer.start()
    print(f"[*] RecTrace File Watcher listening on: {inbox_dir}")
    return observer


def run_daemon(host: str = "0.0.0.0", port: int = 8000):
    """Run the watcher and FastAPI server."""
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    MOCK_PROJECT_DIR.mkdir(parents=True, exist_ok=True)

    observer = start_watcher(INBOX_DIR)

    config = uvicorn.Config(app=app, host=host, port=port, log_level="info")
    server = uvicorn.Server(config)

    print(f"[*] RecTrace FastAPI status server running on http://{host}:{port}")
    try:
        server.run()
    finally:
        observer.stop()
        observer.join()
        print("[*] RecTrace Daemon shutdown cleanly.")


if __name__ == "__main__":
    run_daemon()
