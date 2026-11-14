"""Run the client's scripted test and compare its state hashes with the runner's.

    python tools/check_client.py --godot PATH_TO_GODOT

Needs the engine library in client/bin (see tools/build_client.py) and the runner built
with `cargo build --release`. Exits with status 1 if any step differs.
"""

from __future__ import annotations

import argparse
import shutil
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
        runner = subprocess.run(
            [str(args.runner), "run", str(ROOT / "models" / "toy" / "scenarios" / "client_check.toml"),
             "--columns", "step,hash", "--out", str(runner_out)],
            capture_output=True, text=True, timeout=600)
        if runner.returncode != 0:
            print(runner.stderr.strip(), file=sys.stderr)
            return 1
        theirs = runner_out.read_text().splitlines()
        # The bridge driven directly, then the real interface driven through its controls.
        for script, extra in (("res://tests/scripted_run.gd", []),
                              ("res://tests/ui_run.gd", ["--scenario=models/toy/scenarios/baseline.toml"])):
            client_out.unlink(missing_ok=True)
            client = subprocess.run(
                [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", script,
                 "--", f"--out={client_out}", *extra],
                capture_output=True, text=True, timeout=900)
            print(client.stdout.strip().splitlines()[-1] if client.stdout.strip() else "")
            if client.returncode != 0 or not client_out.exists():
                print(client.stderr.strip()[-3000:], file=sys.stderr)
                print(f"{script} failed", file=sys.stderr)
                return 1
            ours = client_out.read_text().splitlines()
            if ours != theirs:
                for number, (a, b) in enumerate(zip(ours, theirs)):
                    if a != b:
                        print(f"{script}: first difference at line {number + 1}:\n  client {a}\n  runner {b}", file=sys.stderr)
                        break
                else:
                    print(f"{script}: client {len(ours)} lines, runner {len(theirs)}", file=sys.stderr)
                return 1
            print(f"{script}: client and runner agree on all {len(ours) - 1} steps")
        # Hot reload, on a copy of Valmora so the repository's files are never edited.
        copy = folder / "valmora"
        shutil.copytree(ROOT / "models" / "valmora", copy)
        reload = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/reload_run.gd",
             "--", f"--model-dir={copy}", f"--scenario={copy / 'scenarios' / 'term.toml'}"],
            capture_output=True, text=True, timeout=900)
        if reload.returncode != 0:
            print(reload.stdout.strip()[-2000:], reload.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/reload_run.gd failed", file=sys.stderr)
            return 1
        print(reload.stdout.strip().splitlines()[-1])
        second = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/second_model.gd",
             "--", "--scenario=models/mini/scenarios/island.toml"],
            capture_output=True, text=True, timeout=900)
        if second.returncode != 0:
            print(second.stdout.strip()[-2000:], second.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/second_model.gd failed", file=sys.stderr)
            return 1
        print(second.stdout.strip().splitlines()[-1])
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
