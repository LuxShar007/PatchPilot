"""PatchPilot Laptop Bridge Daemon.

Monitors an inbox folder for incoming .patch files, applies them to mock_project
using git, runs the pytest CI/CD suite, and serves real-time status over FastAPI.
"""

import collections
import datetime
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

# Directory configurations
BASE_DIR = Path(__file__).resolve().parent
INBOX_DIR = BASE_DIR / "inbox_patches"
MOCK_PROJECT_DIR = BASE_DIR / "mock_project"

# Rolling history of the last 10 applied patches
MAX_HISTORY_LEN = 10
patch_history: collections.deque = collections.deque(maxlen=MAX_HISTORY_LEN)
processed_patches: set = set()
history_lock = threading.Lock()

# FastAPI application
app = FastAPI(
    title="PatchPilot Laptop Bridge",
    description="Automated git patch runner and CI/CD verification bridge",
    version="1.0.0",
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


@app.get("/")
def root():
    return {
        "service": "PatchPilot Laptop Bridge",
        "status": "online",
        "inbox_directory": str(INBOX_DIR),
        "mock_project_directory": str(MOCK_PROJECT_DIR),
    }


@app.get("/health")
def health():
    return {"status": "healthy", "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()}


@app.get("/status")
def get_status() -> Dict[str, Any]:
    """Return the last 10 applied patches and test results."""
    with history_lock:
        history_list = list(patch_history)
        last_result = history_list[-1] if history_list else None
    return {
        "total_patches_recorded": len(history_list),
        "last_result": last_result,
        "recent_patches": history_list,
    }


from pydantic import BaseModel


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

    # Step 1: Execute git apply
    try:
        git_bin = get_git_command()
        git_cmd = [git_bin, "-C", str(MOCK_PROJECT_DIR), "apply", str(patch_path.resolve())]
        git_result = subprocess.run(
            git_cmd,
            capture_output=True,
            text=True,
            check=False,
        )
        record["git_apply_output"] = (git_result.stdout + "\n" + git_result.stderr).strip()

        if git_result.returncode != 0:
            record["git_apply_status"] = "FAILED"
            record["build_status"] = "GIT APPLY FAILED"
            print(f"[✗] GIT APPLY FAILED for {patch_name}: {record['git_apply_output']}")
            with history_lock:
                patch_history.append(record)
            return record

        record["git_apply_status"] = "SUCCESS"
        print(f"[✓] Git patch applied successfully: {patch_name}")
    except Exception as e:
        record["git_apply_status"] = "ERROR"
        record["git_apply_output"] = str(e)
        record["build_status"] = "GIT APPLY ERROR"
        print(f"[✗] Error executing git apply: {e}")
        with history_lock:
            patch_history.append(record)
        return record

    # Step 2: Run pytest suite on mock_project
    try:
        pytest_cmd = [sys.executable, "-m", "pytest", str(MOCK_PROJECT_DIR)]
        test_result = subprocess.run(
            pytest_cmd,
            capture_output=True,
            text=True,
            check=False,
        )
        record["test_output"] = (test_result.stdout + "\n" + test_result.stderr).strip()

        # Step 3: Log verification results
        if test_result.returncode == 0:
            record["test_status"] = "PASSED"
            record["build_status"] = "BUILD PASSING"
            print(f"[✓] BUILD PASSING - Tests passed for patch {patch_name}")
        else:
            record["test_status"] = "FAILED"
            record["build_status"] = "BUILD FAILED"
            print(f"[✗] BUILD FAILED - Tests failed for patch {patch_name}")
    except Exception as e:
        record["test_status"] = "ERROR"
        record["test_output"] = str(e)
        record["build_status"] = "TEST RUNNER ERROR"
        print(f"[✗] Error executing test suite: {e}")

    with history_lock:
        patch_history.append(record)

    return record


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


ROOT_INBOX_DIR = BASE_DIR.parent / "inbox_patches"


def start_watcher(inbox_dir: Path) -> Observer:
    """Start watchdog observer on inbox directory and repo root inbox."""
    inbox_dir.mkdir(parents=True, exist_ok=True)
    event_handler = PatchInboxHandler()
    observer = Observer()
    observer.schedule(event_handler, path=str(inbox_dir), recursive=False)
    
    # Also monitor parent/root inbox_patches if distinct
    if ROOT_INBOX_DIR.resolve() != inbox_dir.resolve():
        ROOT_INBOX_DIR.mkdir(parents=True, exist_ok=True)
        observer.schedule(event_handler, path=str(ROOT_INBOX_DIR), recursive=False)
        print(f"[*] PatchPilot File Watcher listening on: {ROOT_INBOX_DIR}")

    observer.start()
    print(f"[*] PatchPilot File Watcher listening on: {inbox_dir}")
    return observer


def run_daemon(host: str = "0.0.0.0", port: int = 8000):
    """Run the watcher and FastAPI server."""
    # Ensure inbox and mock project directories exist
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    MOCK_PROJECT_DIR.mkdir(parents=True, exist_ok=True)

    observer = start_watcher(INBOX_DIR)

    config = uvicorn.Config(app=app, host=host, port=port, log_level="info")
    server = uvicorn.Server(config)

    print(f"[*] PatchPilot FastAPI status server running on http://{host}:{port}")
    try:
        server.run()
    finally:
        observer.stop()
        observer.join()
        print("[*] PatchPilot Daemon shutdown cleanly.")


if __name__ == "__main__":
    run_daemon()
