#!/usr/bin/env python3
"""Fail CI if any shipped Android SQLite binary omits the authorizer API.

Unlike Linux unit tests, this inspects the *packaged* Android native assets.
An absent sqlite3_set_authorizer makes read-only restore preview fail closed.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile


REQUIRED_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
REQUIRED_SYMBOL = "sqlite3_set_authorizer"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: assert_android_sqlite_authorizer.py app-debug.apk", file=sys.stderr)
        return 2

    with ZipFile(sys.argv[1]) as apk, tempfile.TemporaryDirectory() as work:
        for abi in REQUIRED_ABIS:
            member = f"lib/{abi}/libsqlite3.so"
            if member not in apk.namelist():
                print(f"FAIL: {member} missing from APK", file=sys.stderr)
                return 1
            binary = Path(work) / f"sqlite3-{abi}.so"
            binary.write_bytes(apk.read(member))
            output = subprocess.run(
                ["readelf", "--wide", "--dyn-syms", str(binary)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            found = any(
                re.search(r"\bFUNC\s+GLOBAL\s+DEFAULT\b", line)
                and line.rstrip().endswith(REQUIRED_SYMBOL)
                for line in output.splitlines()
            )
            if not found:
                print(f"FAIL: {member} lacks {REQUIRED_SYMBOL}", file=sys.stderr)
                return 1
            print(f"PASS: {member} exports {REQUIRED_SYMBOL}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
