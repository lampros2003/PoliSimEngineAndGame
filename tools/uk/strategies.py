"""Play the eight strategies of docs/S13-BALANCE.md through the engine and print the table.

    python tools/uk/strategies.py              every strategy
    python tools/uk/strategies.py a c          some of them
    python tools/uk/strategies.py --months a   and each strategy's figures every six months
    python tools/uk/strategies.py --param vote_finances_effect=1.5 a c   a parameter changed

Each strategy is a list of bills, each made in its month of the 2025 scenario and, if the
Commons or political capital refuses it, made again each month until it passes. Every
question is given its first answer (strategy b: its second). The figures are those of
docs/S13-BALANCE.md's tables: approval is the player's party's rating (`own_support`), the
balance is at an annual rate, capital is counted from January 2025 to June 2029.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from engine import Simulation, load_scenario  # noqa: E402

SCENARIO = ROOT / "models" / "uk" / "scenarios" / "2025.toml"
BLOCS = ["CL", "CR", "Lib", "PopR", "Grn", "SNP", "PC", "NI", "Oth"]
JAN26, JAN27, JUN29 = 12, 24, 53
LAST_BILL = 54  # July 2029: bills made after the election are not played


def month(name: str) -> int:
    """'Feb 2025' -> the step it is played in (January 2025 is step 0)."""
    names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    m, y = name.split()
    return (int(y) - 2025) * 12 + names.index(m)


def label(step: int) -> str:
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][step % 12] + f" {2025 + step // 12}"


# A bill: (month, lever, value). A value ("x", f) is the lever's default times f.
STRATEGIES: dict[str, tuple[str, int, list]] = {
    "a": ("Nothing, first answers", 1, []),
    "b": ("Nothing, second answers", 2, []),
    "c": ("Crowd-pleaser", 1, [
        ("Feb 2025", "basic_rate", 0.19), ("Feb 2025", "spending_health", ("x", 1.03)),
        ("Feb 2025", "ev_grant", 3000), ("Feb 2025", "personal_allowance", 13070),
        ("Feb 2025", "benefits_bill", ("x", 1.03)), ("Jun 2025", "insulation_programme", 2e8),
        ("Jul 2025", "vat_rate", 0.19), ("Aug 2025", "spending_education", ("x", 1.03)),
        ("Apr 2026", "social_housing", 3e8), ("Feb 2027", "winter_fuel_payment", 2),
        ("Jan 2028", "free_school_meals", 2), ("Jun 2028", "prescription_charge", 0),
        ("Sep 2028", "bus_fare_cap", 1), ("Dec 2028", "fuel_duty", 47.95),
        ("Feb 2029", "child_benefit_eldest", 1431.2), ("Apr 2029", "spending_social_care", ("x", 1.03)),
        ("Jun 2029", "basic_rate", 0.18)]),
    "d": ("Austerity", 1, [
        ("Feb 2025", "basic_rate", 0.21), ("Feb 2025", "spending_general", ("x", 0.95)),
        ("Feb 2025", "vat_rate", 0.21), ("Feb 2025", "benefits_bill", ("x", 0.97)),
        ("Feb 2025", "public_investment_bill", ("x", 0.95)), ("Feb 2025", "spending_health", ("x", 0.98)),
        ("Feb 2025", "subsidies_bill", ("x", 0.95)), ("Mar 2025", "transfers_abroad_bill", ("x", 0.9)),
        ("Apr 2025", "spending_education", ("x", 0.98)), ("Jun 2025", "corporation_tax_rate", 0.26),
        ("Jul 2025", "basic_rate", 0.22), ("Aug 2025", "spending_general", ("x", 0.95 ** 2)),
        ("Oct 2025", "vat_rate", 0.22), ("Dec 2025", "benefits_bill", ("x", 0.97 ** 2)),
        ("Mar 2026", "public_investment_bill", ("x", 0.95 ** 2)), ("May 2026", "spending_health", ("x", 0.98 ** 2)),
        ("Jul 2026", "subsidies_bill", ("x", 0.95 ** 2)), ("Oct 2026", "transfers_abroad_bill", ("x", 0.9 ** 2)),
        ("Dec 2026", "spending_education", ("x", 0.98 ** 2)), ("Mar 2027", "corporation_tax_rate", 0.27),
        ("Jun 2027", "basic_rate", 0.23), ("Oct 2027", "spending_general", ("x", 0.95 ** 3)),
        ("Jan 2028", "vat_rate", 0.23), ("Apr 2028", "benefits_bill", ("x", 0.97 ** 3)),
        ("Jul 2028", "public_investment_bill", ("x", 0.95 ** 3)), ("Sep 2028", "spending_health", ("x", 0.98 ** 3)),
        ("Dec 2028", "subsidies_bill", ("x", 0.95 ** 3)), ("Apr 2029", "transfers_abroad_bill", ("x", 0.9 ** 3)),
        ("Jul 2029", "spending_education", ("x", 0.98 ** 3))]),
    "e": ("Reformer", 1, [
        ("Feb 2025", "planning_rules", 4), ("Jun 2025", "sentencing", 4), ("Aug 2025", "alcohol_duty", 1.25),
        ("Nov 2025", "tobacco_duty", 1.25), ("Mar 2026", "fuel_duty", 62.95), ("Nov 2026", "ev_grant", 3000),
        ("Jun 2027", "insulation_programme", 2e8), ("May 2028", "social_housing", 3e8)]),
    "f1": ("Basic rate 30% in Feb 2025", 1, [("Feb 2025", "basic_rate", 0.30)]),
    "f2": ("Health cut by a quarter in Feb 2025", 1, [("Feb 2025", "spending_health", ("x", 0.75))]),
    "g": ("Wrecker", 1, [
        ("Feb 2025", "spending_health", ("x", 0.5)), ("Feb 2025", "basic_rate", 0.35), ("Apr 2025", "vat_rate", 0.30),
        ("Sep 2025", "benefits_bill", ("x", 0.7)), ("Feb 2027", "spending_education", ("x", 0.6))]),
    "h": ("Tax early, please late", 1, [
        ("Feb 2025", "basic_rate", 0.25), ("Feb 2025", "vat_rate", 0.23), ("Jan 2027", "ev_grant", 3000),
        ("Jan 2027", "insulation_programme", 2e8), ("Jan 2027", "winter_fuel_payment", 2),
        ("Jan 2027", "prescription_charge", 0), ("Jul 2027", "social_housing", 3e8), ("Oct 2027", "bus_fare_cap", 1),
        ("Dec 2027", "spending_health", ("x", 1.03)), ("Jan 2029", "free_school_meals", 2),
        ("Mar 2029", "spending_health", ("x", 1.03 ** 2)), ("May 2029", "spending_health", ("x", 1.03 ** 3)),
        ("Jul 2029", "spending_health", ("x", 1.03 ** 4))]),
}


def play(scenario, key: str, steps: int = 60) -> dict:
    """Plays one strategy; returns its rows (one dict a month) and the election's result."""
    _, answer, bills = STRATEGIES[key]
    symbols = scenario.model.symbols
    dilemmas = [d["name"] for d in scenario.model.dilemmas]
    pending = []
    for when, lever, value in bills:
        if isinstance(value, tuple):
            default = symbols[lever].spec["default"]
            value = round(default * value[1]) if symbols[lever].money else default * value[1]
        pending.append((month(when), lever, value))
    sim = Simulation(scenario.model, scenario.seed, scenario.preset, scenario.params, scenario.levers)
    rows, passed, crisis, election = [], 0, None, None
    answers: dict[str, int] = {}
    for step in range(steps):
        made = {}
        for when, lever, value in pending:
            if when <= step <= LAST_BILL and lever not in made:
                made[lever] = (when, lever, value)
        sim.commands = {step: {**{lever: v for _, lever, v in made.values()}, **answers}}
        row = sim.step()
        if made:
            for vote in sim.votes:
                if vote["step"] == step and vote["passed"] and not vote["refused"] and vote["lever"] in made:
                    pending.remove(made[vote["lever"]])
                    passed += 1
        answers = {d: answer for d in dilemmas if row.get(f"{d}_open")}
        if crisis is None and row.get("gilt_crisis_open"):
            crisis = step + 1  # opened at the end of this month: asked at the start of the next
        if row.get("election_now") and election is None:
            seats = sim.column("seats")
            governing = sim.column("governing")
            election = (step, seats, [b for b, g in zip(BLOCS, governing) if g])
        rows.append(row)
    return {"rows": rows, "passed": passed, "crisis": crisis, "election": election}


def capital(rows, last=JUN29):
    earned = sum(r["capital_earned"] for r in rows[:last + 1])
    spent = sum(r["capital_spent"] for r in rows[:last + 1])
    wasted, held = 0.0, 40.0
    for r in rows[:last + 1]:
        before = held - r["capital_spent"] + r["capital_earned"]
        held = r["political_capital"]
        wasted += max(0.0, before - held)
    return earned, spent, wasted


def bn_year(pence) -> float:
    return pence * 12 / 100 / 1e9


def summary(key: str, result: dict) -> str:
    rows = result["rows"]
    step, seats, government = result["election"]
    earned, spent, wasted = capital(rows)
    r = rows[JUN29]
    crisis = label(result["crisis"]) if result["crisis"] is not None else "no"
    return (f"| ({key}) {STRATEGIES[key][0]} | {rows[JAN26]['own_support'] * 100:.1f} / {rows[JAN27]['own_support'] * 100:.1f}"
            f" / {r['own_support'] * 100:.1f}% | {round(seats[0])} | {'+'.join(government)} | {bn_year(r['budget_balance']):+.0f}"
            f" | {r['debt_to_gdp'] * 100:.1f} | {r['gilt_yield_now'] * 100:.2f}% | {r['unemployment_rate'] * 100:.1f}%"
            f" | {result['passed']} | {earned:.0f} / {spent:.0f} / {wasted:.0f} | {crisis} |")


HEADER = ("| Strategy | Approval Jan 2026 / Jan 2027 / Jun 2029 | CL seats | Government after | Balance Jun 2029 £bn/yr"
          " | Debt % GDP | Gilt yield | Unemployment | Bills passed | Capital earned / spent / wasted | Lenders refuse |\n"
          "|---|---|---|---|---|---|---|---|---|---|---|")

EXTRA = ["bank_rate", "mortgage_rate", "homelessness", "productivity"]  # shown by --months when the model has them


def months(key: str, result: dict) -> str:
    rows = result["rows"]
    have = [n for n in EXTRA if n in rows[0]]
    out = [f"({key}) month | approval | balance £bn/yr | debt | unempl. | growth | infl. | " + " | ".join(have)]
    for step in list(range(0, len(rows), 6)) + [JUN29]:
        r = rows[step]
        out.append(f"{label(step)} | {r['own_support'] * 100:.1f}% | {bn_year(r['budget_balance']):+.0f} | "
                   f"{r['debt_to_gdp'] * 100:.1f} | {r['unemployment_rate'] * 100:.1f}% | {r['output_growth'] * 100:+.1f}% | "
                   f"{r['consumer_inflation_annual'] * 100:.1f}% | " + " | ".join(f"{r[n]:.4g}" for n in have))
    return "\n".join(out)


def jumps(rows) -> tuple[float, float]:
    """The largest one-month moves of approval and unemployment, in points."""
    a = max(abs(rows[i]["own_support"] - rows[i - 1]["own_support"]) for i in range(1, JUN29 + 1))
    u = max(abs(rows[i]["unemployment_rate"] - rows[i - 1]["unemployment_rate"]) for i in range(1, JUN29 + 1))
    return a * 100, u * 100


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("keys", nargs="*", default=list(STRATEGIES))
    parser.add_argument("--months", action="store_true", help="each strategy's figures every six months")
    parser.add_argument("--param", action="append", default=[], metavar="NAME=VALUE",
                        help="a parameter on top of the scenario's, to try a tuning")
    args = parser.parse_args()
    scenario = load_scenario(SCENARIO)
    for item in args.param:
        name, value = item.split("=")
        scenario.params[name] = float(value)
    results = {key: play(scenario, key) for key in args.keys}
    print(HEADER)
    for key, result in results.items():
        print(summary(key, result))
    print()
    for key, result in results.items():
        a, u = jumps(result["rows"])
        _, seats, _ = result["election"]
        print(f"({key}) election seats " + ", ".join(f"{b} {round(s)}" for b, s in zip(BLOCS, seats))
              + f"; largest month's move: approval {a:.2f} pts, unemployment {u:.2f} pts")
    if args.months:
        for key, result in results.items():
            print()
            print(months(key, result))


if __name__ == "__main__":
    main()
