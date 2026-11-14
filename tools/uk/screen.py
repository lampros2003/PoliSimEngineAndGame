"""Which of the UK model's uncertain parameters matter (stage S6.0).

    python tools/uk/screen.py [--trajectories 10] [--months 60]

Every parameter of the UK model with `low` and `high` presets is a factor (the household
spending pair, whose share of income is derived from its wealth effect, moves together).
Two screens, run on the engine (cargo build --release) from scenarios that override the
parameters:

- one at a time: each factor at low, then high, the rest central;
- elementary effects (Morris): trajectories on the three levels low, central, high, each
  moving one factor a level at a time from a random start, in a random order (a fixed
  seed, so the report is reproducible). For each factor and outcome, mu* is the mean of
  the absolute effects of a level's step and sigma their spread: a large sigma means the
  factor's effect depends on the others.

Outcomes after the given months: GDP, the unemployment rate, borrowing (the deficit, a
year), public debt as a share of GDP, the government's poll rating; and the government's
seats at the first general election (July 2029). Writes models/uk/SENSITIVITY.md.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import io
import random
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "oracle"))
EXE = "polisim.exe" if sys.platform == "win32" else "polisim"
LEVELS = ("low", "central", "high")
SEED = 6

# Factors: label -> parameters that take the same preset together.
GROUPS = {
    "household spending (wealth effect and share of income)": ["spend_out_of_savings", "spend_out_of_income"],
}
OUTCOMES = [  # (column, label, how to show a difference)
    ("gdp", "GDP", lambda d: f"{d * 12 / 1e11:+,.1f}bn"),
    ("unemployment_rate", "Unemployment", lambda d: f"{d * 100:+.2f} pts"),
    ("budget_balance", "Budget balance", lambda d: f"{d * 12 / 1e11:+,.1f}bn"),
    ("debt_to_gdp", "Debt / GDP", lambda d: f"{d * 100:+.1f} pts"),
    ("government_support", "Poll rating", lambda d: f"{d * 100:+.2f} pts"),
    ("seats_at_election", "Seats in 2029", lambda d: f"{d:+.0f}"),
]


def factors(model) -> dict[str, dict[str, dict[str, object]]]:
    """label -> {param: {level: value}}, for every scalar parameter with presets."""
    grouped = {p for members in GROUPS.values() for p in members}
    out = {label: {p: {lv: model.symbols[p].spec[lv] for lv in LEVELS} for p in members}
           for label, members in GROUPS.items()}
    for d in model.symbols.values():
        if d.kind == "param" and not d.dims and all(lv in d.spec for lv in LEVELS) and d.name not in grouped:
            if d.spec["low"] != d.spec["high"]:
                out[d.name] = {d.name: {lv: d.spec[lv] for lv in LEVELS}}
    return out


def run(engine: Path, folder: Path, key: int, overrides: dict[str, object], months: int) -> dict[str, float]:
    scenario = folder / f"run{key}.toml"
    lines = ["[scenario]", f'model = "{(ROOT / "models" / "uk").as_posix()}"', "seed = 2025", f"steps = {months}",
             'preset = "central"', "", "[params]"] + [f"{k} = {v!r}" for k, v in overrides.items()]
    scenario.write_text("\n".join(lines) + "\n", encoding="utf-8")
    columns = "step,gdp,unemployment_rate,budget_balance,debt_to_gdp,government_support,election_now,government_seats"
    done = subprocess.run([str(engine), "run", str(scenario), "--columns", columns], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"run {key} failed: {done.stderr.strip()[-500:]}")
    rows = list(csv.DictReader(io.StringIO(done.stdout)))
    last = rows[-1]
    elected = [r for r in rows if r["election_now"] == "True"]
    out = {c: float(last[c]) for c, _, _ in OUTCOMES if c in last}
    out["seats_at_election"] = float(elected[0]["government_seats"]) if elected else float("nan")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--trajectories", type=int, default=10)
    parser.add_argument("--months", type=int, default=60)
    parser.add_argument("--engine", type=Path, default=ROOT / "target" / "release" / EXE)
    args = parser.parse_args()
    from polisim_oracle import load_model
    space = factors(load_model(ROOT / "models" / "uk"))
    names = list(space)

    def overrides(levels: dict[str, str]) -> dict[str, object]:
        return {p: values[levels[f]] for f in names for p, values in space[f].items() if levels[f] != "central"}

    designs: list[dict[str, str]] = [dict.fromkeys(names, "central")]
    for f in names:
        for lv in ("low", "high"):
            designs.append(dict(dict.fromkeys(names, "central"), **{f: lv}))
    rng = random.Random(SEED)
    trajectories = []
    for _ in range(args.trajectories):
        point = {f: rng.randrange(3) for f in names}
        order = list(names)
        rng.shuffle(order)
        steps = [dict(point)]
        moved = []
        for f in order:
            step = 1 if point[f] == 0 else -1 if point[f] == 2 else rng.choice((-1, 1))
            point[f] += step
            steps.append(dict(point))
            moved.append((f, step))
        trajectories.append((len(designs), moved))
        designs += [{f: LEVELS[i] for f, i in s.items()} for s in steps]
    with tempfile.TemporaryDirectory() as folder, concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda kv: run(args.engine, Path(folder), kv[0], overrides(kv[1]), args.months),
                                enumerate(designs)))
    central = results[0]
    one_at_a_time = {f: (results[1 + 2 * i], results[2 + 2 * i]) for i, f in enumerate(names)}
    effects: dict[str, dict[str, list[float]]] = {f: {c: [] for c, _, _ in OUTCOMES} for f in names}
    for start, moved in trajectories:
        for k, (f, step) in enumerate(moved):
            before, after = results[start + k], results[start + k + 1]
            for c, _, _ in OUTCOMES:
                effects[f][c].append((after[c] - before[c]) * step)

    lines = ["# Which uncertain parameters matter", "",
             f"Generated by `python tools/uk/screen.py` ({len(designs)} runs of {args.months} months on the engine); "
             "do not edit. Stage S6.0 of `docs/S6-PLAN.md`.", "",
             "Every parameter of the UK model with a low and a high preset is a factor; the ranges are in "
             "`tools/uk/assumptions.toml` and `tools/uk/voters.py`. Outcomes are after "
             f"{args.months} months (borrowing and GDP at an annual rate), and the governing blocs' seats at the "
             "July 2029 election.", "",
             "## Central run", "",
             "| " + " | ".join(label for _, label, _ in OUTCOMES) + " |", "|" + "---:|" * len(OUTCOMES),
             "| " + " | ".join(
                 f"{central[c] * 12 / 1e11:,.1f}bn" if c in ("gdp", "budget_balance") else
                 f"{central[c] * 100:.2f}%" if c in ("unemployment_rate", "debt_to_gdp", "government_support") else
                 f"{central[c]:.0f}" for c, _, _ in OUTCOMES) + " |", "",
             "## One at a time: each factor at low and at high, the rest central", "",
             "| Factor | " + " | ".join(label for _, label, _ in OUTCOMES) + " |", "|---|" + "---:|" * len(OUTCOMES)]
    for f in names:
        low, high = one_at_a_time[f]
        lines.append(f"| {f} | " + " | ".join(f"{show(low[c] - central[c])} / {show(high[c] - central[c])}"
                                              for c, _, show in OUTCOMES) + " |")
    lines += ["", "Each cell: low minus central / high minus central.", "",
              "## Elementary effects (Morris)", "",
              f"{args.trajectories} trajectories. mu* is the mean absolute effect of moving the factor one level "
              "(low to central or central to high); sigma the standard deviation of the effects. Factors in order "
              "of their mu* on the poll rating.", "",
              "| Factor | " + " | ".join(f"{label} mu* (sigma)" for _, label, _ in OUTCOMES) + " |",
              "|---|" + "---:|" * len(OUTCOMES)]

    def mu_star(f, c):
        values = [abs(x) for x in effects[f][c] if x == x]
        return statistics.fmean(values) if values else 0.0
    for f in sorted(names, key=lambda f: -mu_star(f, "government_support")):
        cells = []
        for c, _, show in OUTCOMES:
            values = [x for x in effects[f][c] if x == x]
            sigma = statistics.pstdev(values) if len(values) > 1 else 0.0
            cells.append(f"{show(mu_star(f, c)).lstrip('+')} ({show(sigma).lstrip('+')})")
        lines.append(f"| {f} | " + " | ".join(cells) + " |")
    lines += ["", "## Reading it", ""]
    for c, label, show in OUTCOMES:
        ranked = sorted(names, key=lambda f: -mu_star(f, c))[:3]
        lines.append(f"- {label}: " + ", ".join(f"{f} ({show(mu_star(f, c)).lstrip('+')})" for f in ranked) + ".")
    lines += ["",
              "The factors with the largest effects are where calibration should go first; one whose sigma is "
              "large against its mu* acts through the others. The central preset is the calibration; the ranges "
              "are judgements unless the assumptions file names a source.", "",
              "One caveat: the voters' regional intercepts are fitted preset by preset, with time in office already "
              "counting in the base month. Screening moves the time-in-office effect alone, so its rows include a "
              "small shift of the base month's polls (about 0.15 points for a step of one level); the presets "
              "themselves reproduce the base month exactly.", ""]
    out = ROOT / "models" / "uk" / "SENSITIVITY.md"
    out.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"wrote {out.relative_to(ROOT)}: {len(names)} factors, {len(designs)} runs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
