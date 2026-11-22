"""Record, or check, every model's recorded state hashes (models/*/golden/*.hashes.csv).

    python tools/record_goldens.py            re-record every file with the engine
    python tools/record_goldens.py --check    fail if the engine no longer reproduces one

Each file `models/<model>/golden/<name>.hashes.csv` belongs to the scenario
`models/<model>/scenarios/<name>.toml` and keeps its number of steps. A file is written by

    polisim run <scenario> --steps <N> --columns step,hash --out <file>

The hashes pin the engine's behaviour: re-record only on purpose, when a change to the
engine or a model is meant to change results, and say so in the commit. Needs the engine
built (cargo build --release).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "target" / "release" / ("polisim.exe" if sys.platform == "win32" else "polisim")


def goldens() -> list[tuple[Path, Path, int]]:
    """(scenario, golden file, steps) for every recorded file."""
    out = []
    for golden in sorted(ROOT.glob("models/**/golden/*.hashes.csv")):
        scenario = golden.parent.parent / "scenarios" / (golden.name.removesuffix(".hashes.csv") + ".toml")
        steps = len(golden.read_text(encoding="utf-8").splitlines()) - 1
        out.append((scenario, golden, steps))
    return out


def record(scenario: Path, out: Path, steps: int) -> None:
    done = subprocess.run([str(EXE), "run", str(scenario), "--steps", str(steps), "--columns", "step,hash",
                           "--out", str(out)], capture_output=True, encoding="utf-8")
    if done.returncode != 0:
        raise SystemExit(f"{scenario.relative_to(ROOT)}: {done.stderr.strip()}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if a recorded file is not reproduced")
    args = parser.parse_args()
    if not EXE.exists():
        raise SystemExit(f"the engine is not built: {EXE} is missing; run `cargo build --release` first")
    stale = []
    with tempfile.TemporaryDirectory() as folder:
        for scenario, golden, steps in goldens():
            fresh = Path(folder) / golden.name
            record(scenario, fresh, steps)
            same = fresh.read_bytes() == golden.read_bytes()
            print(f"{golden.relative_to(ROOT).as_posix()}: {steps} steps, {'same' if same else 'DIFFERENT'}")
            if not same:
                stale.append(golden)
                if not args.check:
                    golden.write_bytes(fresh.read_bytes())
    if stale and args.check:
        print(f"{len(stale)} recorded file(s) differ from the engine's run")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
