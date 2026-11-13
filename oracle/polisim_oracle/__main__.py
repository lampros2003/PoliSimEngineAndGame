"""Command line: run a scenario and write one CSV row per step.

    python -m polisim_oracle run models/toy/scenarios/baseline.toml --out run.csv

Money columns are whole numbers of minor units (pence), so the file is exact.
"""

from __future__ import annotations

import argparse
import csv
import sys

from . import from_scenario, load_scenario


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="polisim_oracle")
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="run a scenario file")
    run.add_argument("scenario")
    run.add_argument("--out", help="CSV file to write (default: standard output)")
    run.add_argument("--steps", type=int, help="override the scenario's number of steps")
    run.add_argument("--seed", type=int, help="override the scenario's seed")
    run.add_argument("--columns", help="comma-separated columns to write (default: all)")
    args = parser.parse_args(argv)

    scenario = load_scenario(args.scenario)
    if args.seed is not None:
        scenario.seed = args.seed
    sim = from_scenario(scenario)
    rows = sim.run(args.steps if args.steps is not None else scenario.steps)

    handle = open(args.out, "w", newline="", encoding="utf-8") if args.out else sys.stdout
    try:
        fields = args.columns.split(",") if args.columns else list(rows[0])
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if args.out:
            handle.close()
    if args.out:
        print(f"{scenario.name}: {len(rows)} steps, model {scenario.model.model_hash[:12]}, "
              f"final state {rows[-1]['hash'][:12]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
