"""End-to-end verification script for RecTrace Laptop Bridge & Testbed."""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import requests

BASE_DIR = Path(__file__).resolve().parent
MOCK_PROJECT_DIR = BASE_DIR / "mock_project"
INBOX_DIR = BASE_DIR / "inbox_patches"
STATUS_URL = "http://127.0.0.1:8000/status"
HEALTH_URL = "http://127.0.0.1:8000/health"


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


def setup_mock_project_git_repo():
    """Initialize mock_project as a git repository with baseline commit."""
    print("\n[1/6] Setting up mock_project Git repository...")
    git_bin = get_git_command()
    git_dir = MOCK_PROJECT_DIR / ".git"

    # Always ensure baseline buggy app.py is written
    (MOCK_PROJECT_DIR / "app.py").write_text(BASELINE_APP_CODE, encoding="utf-8")

    if not git_dir.exists():
        run_cmd([git_bin, "init", "-b", "main"], cwd=MOCK_PROJECT_DIR, check=False)
        run_cmd([git_bin, "config", "user.email", "rectrace@iqoo.hackathon"], cwd=MOCK_PROJECT_DIR)
        run_cmd([git_bin, "config", "user.name", "RecTrace Testbed"], cwd=MOCK_PROJECT_DIR)
    else:
        # Reset any working tree modifications and switch to main
        run_cmd([git_bin, "checkout", "-B", "main"], cwd=MOCK_PROJECT_DIR, check=False)
        run_cmd([git_bin, "reset", "--hard", "HEAD"], cwd=MOCK_PROJECT_DIR, check=False)
        run_cmd([git_bin, "clean", "-fd"], cwd=MOCK_PROJECT_DIR, check=False)
        (MOCK_PROJECT_DIR / "app.py").write_text(BASELINE_APP_CODE, encoding="utf-8")

    # Ensure baseline app.py and test_app.py are in place
    run_cmd([git_bin, "add", "app.py", "test_app.py"], cwd=MOCK_PROJECT_DIR)
    
    # Check if there are changes to commit
    status = run_cmd([git_bin, "status", "--porcelain"], cwd=MOCK_PROJECT_DIR)
    if status.stdout.strip():
        run_cmd([git_bin, "commit", "-m", "Baseline: Introduce intentional missing role bug"], cwd=MOCK_PROJECT_DIR)
    
    print("[✓] mock_project Git repository initialized at baseline commit.")


def verify_baseline_fails():
    """Verify that running pytest on mock_project fails on baseline."""
    print("\n[2/6] Verifying baseline bug in mock_project...")
    pytest_res = run_cmd([sys.executable, "-m", "pytest", str(MOCK_PROJECT_DIR)], check=False)
    
    assert pytest_res.returncode != 0, "Expected baseline tests to FAIL, but they passed!"
    assert "FAILED" in pytest_res.stdout or "KeyError" in pytest_res.stdout or "KeyError" in pytest_res.stderr
    print("[✓] Confirmed: baseline test suite fails as expected with KeyError on missing role.")


def generate_patch_file() -> str:
    """Generate a standard unified git diff patch fixing app.py."""
    app_file = MOCK_PROJECT_DIR / "app.py"
    original_code = app_file.read_text(encoding="utf-8")
    
    # Temporarily apply fix to read git diff
    target_bug = "return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}"
    target_fix = "role = user_dict.get('role', 'user')\n    return {'name': user_dict['name'], 'role': role.upper(), 'status': 'active'}"
    fixed_code = original_code.replace(target_bug, target_fix)
    app_file.write_text(fixed_code, encoding="utf-8")
    
    git_bin = get_git_command()
    diff_res = run_cmd([git_bin, "diff", "app.py"], cwd=MOCK_PROJECT_DIR)
    patch_content = diff_res.stdout
    
    # Restore original buggy code
    app_file.write_text(original_code, encoding="utf-8")
    
    return patch_content


def test_end_to_end_bridge():
    """Execute complete bridge verification loop."""
    print("=" * 70)
    print("STARTING PATCHPILOT LAPTOP BRIDGE END-TO-END VERIFICATION")
    print("=" * 70)

    # 1. Prepare git repo
    setup_mock_project_git_repo()

    # 2. Confirm baseline test failure
    verify_baseline_fails()

    # 3. Clean inbox
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    for old_file in INBOX_DIR.glob("*.patch"):
        try:
            old_file.unlink()
        except Exception:
            pass

    # 4. Start daemon in background subprocess
    print("\n[3/6] Starting RecTrace daemon on port 8000...")
    daemon_proc = subprocess.Popen(
        [sys.executable, str(BASE_DIR / "daemon.py")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        # Wait for FastAPI server to become responsive
        max_retries = 30
        server_ready = False
        for _ in range(max_retries):
            try:
                resp = requests.get(HEALTH_URL, timeout=1)
                if resp.status_code == 200:
                    server_ready = True
                    break
            except Exception:
                time.sleep(0.3)

        if not server_ready:
            daemon_stdout, daemon_stderr = daemon_proc.communicate(timeout=2)
            raise RuntimeError(
                f"Daemon failed to start within timeout.\nStdout: {daemon_stdout}\nStderr: {daemon_stderr}"
            )

        print("[✓] RecTrace Daemon & FastAPI status endpoint live!")

        # 5. Drop patch into inbox_patches/
        print("\n[4/6] Generating and dropping patch into inbox_patches/...")
        patch_path = INBOX_DIR / "fix_missing_role.patch"
        patch_path.write_text(generate_patch_file(), encoding="utf-8")
        print(f"[✓] Created: {patch_path.name}")

        # 6. Poll status endpoint for completion
        print("\n[5/6] Awaiting daemon processing and CI/CD verification...")
        applied = False
        last_data = None
        for _ in range(30):
            time.sleep(0.5)
            try:
                res = requests.get(STATUS_URL, timeout=2)
                if res.status_code == 200:
                    data = res.json()
                    recent = data.get("recent_patches", [])
                    if recent and recent[-1].get("patch_file") == "fix_missing_role.patch":
                        last_data = recent[-1]
                        applied = True
                        break
            except Exception:
                pass

        assert applied, "Daemon did not process the patch within the timeout period!"
        print(f"[✓] Daemon detected and processed patch: {last_data['patch_file']}")
        print(f"    - Git Apply Status: {last_data['git_apply_status']}")
        print(f"    - Test Status:      {last_data['test_status']}")
        print(f"    - Build Status:     {last_data['build_status']}")

        assert last_data["git_apply_status"] == "SUCCESS", f"Git apply failed: {last_data.get('git_apply_output')}"
        assert last_data["test_status"] == "PASSED", f"Tests failed: {last_data.get('test_output')}"
        assert last_data["build_status"] == "BUILD PASSING", "Build status did not evaluate to BUILD PASSING!"

        # 7. Direct verification of pytest on mock_project
        print("\n[6/6] Confirming mock_project test suite is now green...")
        pytest_res = run_cmd([sys.executable, "-m", "pytest", str(MOCK_PROJECT_DIR)], check=True)
        assert pytest_res.returncode == 0
        assert "passed" in pytest_res.stdout
        # 8. Verification of /create-branch-commit and /git-info
        print("\n[*] Verifying /create-branch-commit and /git-info...")
        branch_res = requests.post(
            "http://127.0.0.1:8000/create-branch-commit",
            json={"branch_name": "rectrace/test-branch", "commit_message": "test: verify automated branch creation"},
            timeout=3,
        )
        assert branch_res.status_code == 200
        branch_data = branch_res.json()
        assert branch_data["status"] == "success"
        assert branch_data["branch"] == "rectrace/test-branch"
        assert branch_data["commit_sha"] is not None

        git_info_res = requests.get("http://127.0.0.1:8000/git-info", timeout=2)
        assert git_info_res.status_code == 200
        assert git_info_res.json()["current_branch"] == "rectrace/test-branch"
        print(f"[✓] Created Git branch {branch_data['branch']} (Commit: {branch_data['commit_sha']})")

        # 9. Verification of /reset-testbed and /run-tests endpoints
        print("\n[*] Verifying /reset-testbed and /run-tests endpoints...")
        reset_res = requests.post("http://127.0.0.1:8000/reset-testbed", timeout=2)
        assert reset_res.status_code == 200
        assert reset_res.json()["status"] == "baseline_reset"

        run_res = requests.post("http://127.0.0.1:8000/run-tests", timeout=2)
        assert run_res.status_code == 200
        assert run_res.json()["status"] == "FAILED"  # Baseline fails with KeyError

        health_res = requests.get("http://127.0.0.1:8000/health", timeout=2)
        assert health_res.status_code == 200
        assert health_res.json()["status"] == "healthy"
        print("[✓] Verified: /create-branch-commit, /git-info, /reset-testbed, /run-tests, and /health work as expected.")

        print("\n" + "=" * 70)
        print("ALL VERIFICATION CHECKS PASSED SUCCESSFULLY! [✓]")
        print("=" * 70)

    finally:
        # Cleanup daemon process
        print("\n[*] Tearing down test daemon process...")
        daemon_proc.terminate()
        try:
            daemon_proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            daemon_proc.kill()
        print("[*] Teardown complete.")


if __name__ == "__main__":
    test_end_to_end_bridge()
