#!/usr/bin/env python3
"""Fail Android CI if the old notification boot receiver is still registered.

This checks the *compiled* APK manifest rather than source XML; manifest
merging may otherwise reintroduce the plugin receiver ahead of our guard.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: assert_safe_boot_receiver.py app-debug.apk", file=sys.stderr)
        return 2
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT", ""))
    tools = sorted(sdk.glob("build-tools/*/aapt"))
    if not tools:
        print("FAIL: Android aapt build tool is unavailable", file=sys.stderr)
        return 1
    manifest = subprocess.run(
        [str(tools[-1]), "dump", "xmltree", sys.argv[1], "AndroidManifest.xml"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    expected = "SafeScheduledNotificationBootReceiver"
    forbidden = "com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
    if expected not in manifest or forbidden in manifest:
        print("FAIL: unsafe or missing boot receiver in merged APK manifest", file=sys.stderr)
        return 1
    print("PASS: native safe boot receiver is registered without plugin receiver")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
