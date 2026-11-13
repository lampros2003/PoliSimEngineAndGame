"""Run random scenarios through the oracle and the engine and compare the results.

    cargo build --release
    python tools/diff_engine.py --count 200

For each scenario both sides must give the same exit code (0 finished, 1 could not
start, 2 failed part-way) and, unless they could not start, the same CSV byte for byte:
every national value and the state hash of every step. Scenarios vary the seed, the
parameter preset, parameter overrides, starting lever settings and scheduled lever
changes, and now and then use values that are out of range or malformed, so that the
refusals are compared as well as the successes.

Exits with status 1 if any scenario differs.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "oracle"))

from polisim_oracle import FormulaError, ModelError, SimError  # noqa: E402
from polisim_oracle.__main__ import main as oracle_main  # noqa: E402

MODEL = ROOT / "models" / "toy"
EXE = "polisim.exe" if sys.platform == "win32" else "polisim"

# lever: (default, lowest allowed, highest allowed, is money)
LEVERS = {
    "gov_purchases": (1_490_000_000, 0, 10_000_000_000, True),
    "benefit_rate": (800, 0, 5000, True),
    "personal_allowance": (1000, 0, 4000, True),
    "basic_rate": (0.20, 0.0, 1.0, False),
    "higher_rate": (0.40, 0.0, 1.0, False),
    "vat_rate": (0.20, 0.0, 1.0, False),
}
# parameter: (lowest, highest, is money); values are drawn a little beyond these limits
PARAMS = {
    "propensity_income": (0.5, 1.0, False),
    "propensity_wealth": (0.0, 0.3, False),
    "wage_share": (0.3, 0.95, False),
    "labour_adjust": (0.0, 1.0, False),
    "separation_rate": (0.0, 0.2, False),
    "payout_rate": (0.0, 1.0, False),
    "higher_threshold": (1500, 9000, True),
}


def toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '"' + value + '"'
    return repr(value)


def lever_value(rng: random.Random, name: str):
    default, low, high, money = LEVERS[name]
    kind = rng.random()
    if kind < 0.80:
        value = default * rng.uniform(0.5, 1.5)
    elif kind < 0.93:
        value = rng.uniform(low, high)
    elif kind < 0.98:
        value = rng.choice([low - (high - low) * 0.1, high * 1.1 + 1])  # outside the declared range
    else:
        return rng.choice([True, "plenty", 0.123456789 if money else "0.2"])  # wrong kind of value
    if money:
        return round(value, 2) if rng.random() < 0.5 else int(value)
    return value


def param_value(rng: random.Random, name: str):
    low, high, money = PARAMS[name]
    span = high - low
    value = rng.uniform(low - 0.05 * span, high + 0.05 * span)
    return round(value, 2) if money else value


def make_scenario(rng: random.Random) -> str:
    steps = rng.randrange(1, 41)
    seed = rng.choice([rng.randrange(0, 1 << 63), rng.randrange(-(1 << 63), 0), rng.randrange(0, 100)])
    lines = ["[scenario]", f'model = "{MODEL.as_posix()}"', f"seed = {seed}", f"steps = {steps}",
             f'preset = "{rng.choice(["low", "central", "central", "high"])}"', ""]
    params = {name: param_value(rng, name) for name in PARAMS if rng.random() < 0.15}
    if rng.random() < 0.02:
        params["no_such_parameter"] = 1
    if params:
        lines += ["[params]"] + [f"{k} = {toml_value(v)}" for k, v in params.items()] + [""]
    levers = {name: lever_value(rng, name) for name in LEVERS if rng.random() < 0.2}
    if levers:
        lines += ["[levers]"] + [f"{k} = {toml_value(v)}" for k, v in levers.items()] + [""]
    for _ in range(rng.choice([0, 0, 1, 2, 3, 6])):
        names = rng.sample(sorted(LEVERS), rng.choice([1, 1, 2]))
        if rng.random() < 0.02:
            names.append("not_a_lever")
        settings = ", ".join(f"{n} = {toml_value(lever_value(rng, n) if n in LEVERS else 1)}" for n in names)
        lines += ["[[command]]", f"step = {rng.randrange(0, steps + 2)}", f"set = {{ {settings} }}", ""]
    return "\n".join(lines)


def run_oracle(scenario: Path, out: Path) -> int:
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            return oracle_main(["run", str(scenario), "--out", str(out)])
    except (ModelError, FormulaError, SimError):
        return 1  # could not start, or a malformed command: the command line would stop here


def run_engine(engine: Path, scenario: Path, out: Path) -> int:
    return subprocess.run([str(engine), "run", str(scenario), "--out", str(out)], capture_output=True).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--engine", type=Path, default=ROOT / "target" / "release" / EXE)
    args = parser.parse_args()
    if not args.engine.exists():
        print(f"engine not found at {args.engine}; run `cargo build --release` first", file=sys.stderr)
        return 1

    rng = random.Random(args.seed)
    outcomes = {0: 0, 1: 0, 2: 0}
    steps_compared = 0
    differences = []
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        for index in range(args.count):
            text = make_scenario(rng)
            scenario = folder / f"s{index}.toml"
            scenario.write_text(text, encoding="utf-8")
            oracle_csv, engine_csv = folder / f"o{index}.csv", folder / f"e{index}.csv"
            oracle_code = run_oracle(scenario, oracle_csv)
            engine_code = run_engine(args.engine, scenario, engine_csv)
            problem = None
            if oracle_code != engine_code:
                problem = f"exit codes differ: oracle {oracle_code}, engine {engine_code}"
            elif oracle_code != 1:
                oracle_bytes, engine_bytes = oracle_csv.read_bytes(), engine_csv.read_bytes()
                if oracle_bytes != engine_bytes:
                    problem = "CSV output differs"
                steps_compared += max(oracle_bytes.count(b"\n") - 1, 0)
            outcomes[oracle_code] += 1
            if problem:
                differences.append((index, problem, text))

    print(f"{args.count} scenarios: {outcomes[0]} finished, {outcomes[2]} failed part-way, "
          f"{outcomes[1]} could not start; {steps_compared} steps compared")
    for index, problem, text in differences[:5]:
        print(f"\n--- scenario {index}: {problem}\n{text}")
    if differences:
        print(f"\n{len(differences)} scenario(s) differ")
        return 1
    print("oracle and engine agree on every scenario")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
