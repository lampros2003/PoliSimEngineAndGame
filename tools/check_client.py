"""Run the client's scripted test and compare its state hashes with the runner's.

    python tools/check_client.py --godot PATH_TO_GODOT

Needs the engine library in client/bin (see tools/build_client.py) and the runner built
with `cargo build --release`. Exits with status 1 if any step differs.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = "polisim.exe" if sys.platform == "win32" else "polisim"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--godot", required=True, help="Godot executable (the console one on Windows)")
    parser.add_argument("--runner", type=Path, default=ROOT / "target" / "release" / EXE)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        client_out, runner_out = folder / "client.csv", folder / "runner.csv"
        client = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/scripted_run.gd",
             "--", f"--out={client_out}"],
            capture_output=True, text=True, timeout=600)
        print(client.stdout.strip())
        if client.returncode != 0 or not client_out.exists():
            print(client.stderr.strip(), file=sys.stderr)
            print("the client's scripted run failed", file=sys.stderr)
            return 1
        runner = subprocess.run(
            [str(args.runner), "run", str(ROOT / "models" / "toy" / "scenarios" / "client_check.toml"),
             "--columns", "step,hash", "--out", str(runner_out)],
            capture_output=True, text=True, timeout=600)
        if runner.returncode != 0:
            print(runner.stderr.strip(), file=sys.stderr)
            return 1
        ours = client_out.read_text().splitlines()
        theirs = runner_out.read_text().splitlines()
        if ours != theirs:
            for number, (a, b) in enumerate(zip(ours, theirs)):
                if a != b:
                    print(f"first difference at line {number + 1}:\n  client {a}\n  runner {b}", file=sys.stderr)
                    break
            else:
                print(f"different lengths: client {len(ours)} lines, runner {len(theirs)}", file=sys.stderr)
            return 1
        print(f"client and runner agree on all {len(ours) - 1} steps")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
