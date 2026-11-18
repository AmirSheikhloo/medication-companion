#!/usr/bin/env python3
"""Hard process-death Android regression driven OUTSIDE instrumentation.

The only exported entrypoint exists in the DEBUG manifest, is rejected for
all callers except the same app UID or Android SHELL_UID, and operates solely
in freshly generated, isolated synthetic no_backup/backup_journal_probe UUIDs.
No production database, reminder, or Phase B restore path is touched.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

ADB = os.environ.get("ADB_PATH", "adb")
DEVICE = os.environ.get("ANDROID_SERIAL", "emulator-5554")
RUN = os.environ.get("GITHUB_RUN_NUMBER", "")
if not RUN.isdigit():
    raise SystemExit("FAIL: expected CI run number for isolated debug application ID")
PACKAGE = f"ir.example.medication_companion.m4r{RUN}"
URI = f"content://{PACKAGE}.m4killprobe"
APK = Path("apps/mobile/build/app/outputs/flutter-apk/app-debug.apk")


def adb(*args: str, timeout: int = 35) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ADB, "-s", DEVICE, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def call(method: str, probe_id: str | None = None, timeout: int = 35) -> str:
    args = ["shell", "content", "call", "--uri", URI, "--method", method]
    if probe_id is not None:
        args += ["--arg", probe_id]
    response = adb(*args, timeout=timeout)
    output = response.stdout + "\n" + response.stderr
    if response.returncode != 0 or "Result: Bundle" not in output:
        raise RuntimeError(
            f"debug provider call {method} failed (exit={response.returncode}): {output[-900:]}"
        )
    return output


def require_field(output: str, name: str) -> str:
    match = re.search(rf"(?:^|[\s{{,]){re.escape(name)}=([^,\]\s}}]+)", output)
    if match is None:
        raise AssertionError(f"debug provider result has no {name}: {output[-600:]}")
    return match.group(1)


def main() -> None:
    if not APK.is_file():
        raise AssertionError(f"APK not found: {APK}")
    installed = adb("shell", "pm", "list", "packages", PACKAGE)
    if installed.returncode != 0:
        raise AssertionError(installed.stderr)
    if f"package:{PACKAGE}" not in installed.stdout.split():
        installed = adb("install", "-r", "--no-streaming", str(APK), timeout=90)
        if installed.returncode != 0 or "Success" not in installed.stdout:
            raise AssertionError("Could not install debug target: " + installed.stdout + installed.stderr)

    for checkpoint in ("OLD_SAVED", "NEW_INSTALLED"):
        probe_id = str(uuid.uuid4())
        first_pid = int(require_field(call("pid"), "pid"))
        print(f"D3d {checkpoint}: process pid before kill = {first_pid}", flush=True)

        # Killing the remote provider breaks this ADB Binder invocation.
        # An exception/timeout here is NOT itself evidence of correct recovery.
        try:
            response = adb(
                "shell", "content", "call", "--uri", URI,
                "--method", "kill_" + checkpoint, "--arg", probe_id, timeout=40,
            )
            print(f"D3d {checkpoint}: kill RPC exit={response.returncode}", flush=True)
        except subprocess.TimeoutExpired:
            print(f"D3d {checkpoint}: kill RPC timed out after process death", flush=True)

        recovered = None
        last_error: Exception | None = None
        for _ in range(12):
            try:
                recovered = call("recover_" + checkpoint, probe_id, timeout=35)
                break
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                last_error = error
                time.sleep(0.25)
        if recovered is None:
            raise AssertionError(f"No cold reentry for {checkpoint}: {last_error}")

        second_pid = int(require_field(recovered, "pid"))
        actual_terminal = require_field(recovered, "terminal")
        expected_terminal = "ROLLED_BACK" if checkpoint == "OLD_SAVED" else "COMMITTED"
        if first_pid == second_pid:
            raise AssertionError(f"Process did not die across {checkpoint}: pid={first_pid}")
        if require_field(recovered, "ok") != "true" or actual_terminal != expected_terminal:
            raise AssertionError(f"Wrong terminal journal result: {recovered[-1000:]}")
        cleanup = call("cleanup", probe_id)
        if require_field(cleanup, "ok") != "true":
            raise AssertionError(f"Cleanup failed after {checkpoint}")
        print(f"PASS D3d {checkpoint}: pid {first_pid} -> {second_pid}; {actual_terminal}", flush=True)

    print("PASS D3d: both real Android process-death checkpoints recovered", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as failure:
        print(f"FAIL D3d: {failure}", file=sys.stderr)
        raise SystemExit(1) from failure
