"""Copy the engine library into the Godot project and refresh Godot's import cache.

    cargo build --release -p polisim-godot
    python tools/build_client.py --godot PATH_TO_GODOT

Godot loads extensions listed in client/.godot/extension_list.cfg, which only the editor
writes; `--import` makes it do so without opening a window.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = {"win32": "polisim_godot.dll", "darwin": "libpolisim_godot.dylib"}.get(sys.platform, "libpolisim_godot.so")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--godot", help="Godot executable; skip the import step if omitted")
    parser.add_argument("--profile", default="release")
    args = parser.parse_args()
    built = ROOT / "target" / args.profile / LIBRARY
    if not built.exists():
        print(f"{built} not found; run `cargo build --release -p polisim-godot` first", file=sys.stderr)
        return 1
    (ROOT / "client" / "bin").mkdir(exist_ok=True)
    shutil.copy2(built, ROOT / "client" / "bin" / LIBRARY)
    print(f"copied {LIBRARY} into client/bin")
    if args.godot:
        # On a fresh checkout, Godot 4.7.2's editor aborts while quitting from its first
        # import when the library is present (exit code 134); the import itself has been
        # written by then, and the game runs normally. A second import with the cache in
        # place exits cleanly, so that one is the check.
        command = [args.godot, "--headless", "--path", str(ROOT / "client"), "--import"]
        first = subprocess.run(command, capture_output=True, text=True, timeout=600)
        if first.returncode != 0:
            print(f"first import exited with {first.returncode}; importing again")
        done = subprocess.run(command, capture_output=True, text=True, timeout=600)
        listed = ROOT / "client" / ".godot" / "extension_list.cfg"
        if done.returncode != 0 or not listed.exists():
            print(done.stdout[-2000:], done.stderr[-2000:], sep="\n", file=sys.stderr)
            print("Godot did not register the extension", file=sys.stderr)
            return 1
        print("Godot registered the extension")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
