"""How long a month of the UK model takes with more households (stage S4.4).

    python tools/uk/bench_households.py [--records 100000] [--months 24] [--profile N]

Builds the households afresh at the size asked for (tools/uk/households.py), writes a copy
of the UK model that uses them into a temporary folder (tools/uk/calibrate.py), and runs it
with the engine, printing the time per month and per phase. The repository's model is not
touched. Needs the engine built (cargo build --release) and the ONS tables households.py
reads, downloaded with `python tools/uk/pipeline.py fetch households2025 ashe3 ashe6`.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
EXE = "polisim.exe" if sys.platform == "win32" else "polisim"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--records", type=int, default=100_000)
    parser.add_argument("--months", type=int, default=24)
    parser.add_argument("--engine", type=Path, default=ROOT / "target" / "release" / EXE)
    parser.add_argument("--profile", type=int, default=0, help="also list the N slowest formulas (stage S10)")
    args = parser.parse_args()
    import calibrate
    import households
    with tempfile.TemporaryDirectory() as folder:
        model = Path(folder) / "uk"
        shutil.copytree(ROOT / "models" / "uk", model, ignore=shutil.ignore_patterns("hindcast", "golden"))
        if households.main(["--records", str(args.records), "--out", str(model / "households")]) != 0:
            return 1
        calibrate.write_model(calibrate.DEFAULT_BASE, model, households=model / "households")
        run = subprocess.run([str(args.engine), "run", str(model / "scenarios" / "2025.toml"), "--steps",
                              str(args.months), "--columns", "step", "--time"]
                             + (["--profile", str(args.profile)] if args.profile else []), capture_output=True, encoding="utf-8")
        print(run.stderr.strip())
        return run.returncode


if __name__ == "__main__":
    sys.exit(main())
