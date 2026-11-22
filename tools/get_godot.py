"""Download the official Godot build for this system and check it against the release's
published SHA-512 sums.

    python tools/get_godot.py --to .godot-bin

Prints the path of the executable to use for scripted runs (on Windows, the console one).
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.7.2-stable"
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}"
ARCHIVE = {"win32": f"Godot_v{VERSION}_win64.exe.zip"}.get(sys.platform, f"Godot_v{VERSION}_linux.x86_64.zip")
RUN = {"win32": f"Godot_v{VERSION}_win64_console.exe"}.get(sys.platform, f"Godot_v{VERSION}_linux.x86_64")


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=300) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--to", type=Path, required=True)
    args = parser.parse_args()
    target = args.to / RUN
    if not target.exists():
        sums = fetch(f"{BASE}/SHA512-SUMS.txt").decode()
        expected = next(line.split()[0] for line in sums.splitlines() if line.endswith(" " + ARCHIVE))
        data = fetch(f"{BASE}/{ARCHIVE}")
        if hashlib.sha512(data).hexdigest() != expected:
            print(f"{ARCHIVE}: checksum does not match the release's SHA512-SUMS.txt", file=sys.stderr)
            return 1
        args.to.mkdir(parents=True, exist_ok=True)
        archive = args.to / ARCHIVE
        archive.write_bytes(data)
        with zipfile.ZipFile(archive) as z:
            for name in z.namelist():
                if "/" in name or "\\" in name or ".." in name:
                    print(f"unexpected path in archive: {name}", file=sys.stderr)
                    return 1
            z.extractall(args.to)
        archive.unlink()
        if sys.platform != "win32":
            target.chmod(0o755)
    print(target.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
