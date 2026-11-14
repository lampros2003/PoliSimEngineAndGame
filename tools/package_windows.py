"""Assemble the Windows test build: Godot, the game project, the engine library, the
models, the command-line runner and the benchmark, with a launcher.

    python tools/package_windows.py --godot-dir .godot-bin --out dist/PoliSim

Run on Windows after tools/build_client.py (so the project's import cache exists).
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = "4.7.2-stable"

LAUNCHER = f"""@echo off
rem Starts PoliSim. Godot runs the game project in the "game" folder.
start "" "%~dp0godot\\Godot_v{VERSION}_win64.exe" --path "%~dp0game"
"""

README = """PoliSim test build
==================

Start the game with PoliSim.bat.

Windows may warn that the file is from an unknown publisher: the build is not signed.
Choose "More info", then "Run anyway".

Contents
  PoliSim.bat     starts the game
  game\\           the game project, the engine library and the models
  godot\\          the Godot 4.7.2 engine that runs it (official build)
  tools\\          polisim.exe, the command-line runner, and polisim-s0-bench.exe

Optional: measure this computer's speed
  Open a command prompt in the tools folder and run
      polisim-s0-bench.exe > bench.txt
  then send bench.txt back. It takes about a minute.

Optional: play in the terminal instead
      tools\\polisim.exe play game\\models\\toy\\scenarios\\baseline.toml
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--godot-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out
    if out.exists():
        shutil.rmtree(out)
    (out / "godot").mkdir(parents=True)
    (out / "tools").mkdir()
    for exe in (f"Godot_v{VERSION}_win64.exe", f"Godot_v{VERSION}_win64_console.exe"):
        shutil.copy2(args.godot_dir / exe, out / "godot" / exe)
    ignore = shutil.ignore_patterns("tests", "*.tmp")
    shutil.copytree(ROOT / "client", out / "game", ignore=ignore)
    shutil.copytree(ROOT / "models", out / "game" / "models")
    for exe in (ROOT / "target" / "release" / "polisim.exe", ROOT / "bench" / "s0" / "target" / "release" / "polisim-s0-bench.exe"):
        if exe.exists():
            shutil.copy2(exe, out / "tools" / exe.name)
        else:
            print(f"warning: {exe} not built, left out", file=sys.stderr)
    (out / "PoliSim.bat").write_text(LAUNCHER, newline="\r\n")
    (out / "README.txt").write_text(README, newline="\r\n")
    if not (out / "game" / "bin" / "polisim_godot.dll").exists():
        print("the engine library is missing from game/bin", file=sys.stderr)
        return 1
    if not (out / "game" / ".godot" / "extension_list.cfg").exists():
        print("the project has not been imported (run tools/build_client.py --godot)", file=sys.stderr)
        return 1
    print(f"assembled {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
