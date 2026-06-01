#!@python@
from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path


LLDB = "@lldb@"
LLDB_MCP = "@lldb_mcp@"
LLDB_LAUNCH_COMMAND = "protocol start MCP"
STARTUP_TIMEOUT_ENV = "LLDB_MCP_STARTUP_TIMEOUT"
DEFAULT_STARTUP_TIMEOUT_SECONDS = 30.0
STATE_SUBDIR = "lldb-mcp"


def is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def cleanup_stale_registries(registry_dir: Path) -> None:
    for registry in registry_dir.glob("lldb-mcp-*.json"):
        try:
            pid = int(registry.stem.removeprefix("lldb-mcp-"))
        except ValueError:
            continue
        if not is_running(pid):
            try:
                registry.unlink(missing_ok=True)
            except OSError:
                continue


def registries(registry_dir: Path) -> list[Path]:
    cleanup_stale_registries(registry_dir)
    return list(registry_dir.glob("lldb-mcp-*.json"))


def start_lldb(log_file: Path) -> subprocess.Popen[bytes]:
    with log_file.open("ab", buffering=0) as log:
        return subprocess.Popen(
            [LLDB, "-O", LLDB_LAUNCH_COMMAND],
            stdin=subprocess.PIPE,
            stdout=log,
            stderr=subprocess.STDOUT,
        )


def startup_timeout() -> float:
    value = os.environ.get(STARTUP_TIMEOUT_ENV)
    if value is None:
        return DEFAULT_STARTUP_TIMEOUT_SECONDS
    try:
        timeout = float(value)
    except ValueError as error:
        raise ValueError(f"invalid {STARTUP_TIMEOUT_ENV}: {value}") from error
    if timeout <= 0:
        raise ValueError(f"{STARTUP_TIMEOUT_ENV} must be positive")
    return timeout


def xdg_state_home() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        return Path(state_home)
    return Path.home() / ".local/state"


def wait_for_registry(registry_dir: Path, process: subprocess.Popen[bytes]) -> None:
    deadline = time.monotonic() + startup_timeout()
    while time.monotonic() < deadline:
        if registries(registry_dir):
            return
        if process.poll() is not None:
            raise RuntimeError(
                f"LLDB exited before starting MCP server: {process.returncode}"
            )
        time.sleep(0.1)
    raise TimeoutError("timed out waiting for LLDB MCP server to start")


def terminate(process: subprocess.Popen[bytes]) -> None:
    if process.stdin is not None:
        process.stdin.close()
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def run_lldb_mcp() -> int:
    env = os.environ.copy()
    env["LLDB_EXE_PATH"] = LLDB
    return subprocess.run([LLDB_MCP], env=env).returncode


def main() -> int:
    registry_dir = Path.home() / ".lldb"
    state_dir = xdg_state_home() / STATE_SUBDIR
    registry_dir.mkdir(parents=True, exist_ok=True)
    state_dir.mkdir(parents=True, exist_ok=True)

    started_server: subprocess.Popen[bytes] | None = None
    try:
        if not registries(registry_dir):
            started_server = start_lldb(state_dir / "lldb.log")
            wait_for_registry(registry_dir, started_server)
        return run_lldb_mcp()
    except Exception as error:
        print(f"lldb-mcp-launcher: {error}", file=sys.stderr)
        return 1
    finally:
        if started_server is not None:
            terminate(started_server)


if __name__ == "__main__":
    def handle_sigterm(signum: int, _frame: object) -> None:
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, handle_sigterm)
    raise SystemExit(main())
