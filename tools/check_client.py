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
            capture_output=True, encoding="utf-8", timeout=600)
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
                capture_output=True, encoding="utf-8", timeout=900)
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
            capture_output=True, encoding="utf-8", timeout=900)
        if reload.returncode != 0:
            print(reload.stdout.strip()[-2000:], reload.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/reload_run.gd failed", file=sys.stderr)
            return 1
        print(reload.stdout.strip().splitlines()[-1])
        # Stage S7.3: a recession brought on, announced and shown.
        situations = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/situations_check.gd",
             "--", "--scenario=models/uk/scenarios/2025.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if situations.returncode != 0:
            print(situations.stdout.strip()[-2000:], situations.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/situations_check.gd failed", file=sys.stderr)
            return 1
        print(situations.stdout.strip().splitlines()[-1])
        # Stage S9.1: a dilemma asked, waited for and answered (Valmora's dock strike mod).
        dilemma = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/dilemma_check.gd",
             "--", "--scenario=models/valmora/scenarios/dock_strike.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if dilemma.returncode != 0:
            print(dilemma.stdout.strip()[-2000:], dilemma.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/dilemma_check.gd failed", file=sys.stderr)
            return 1
        print(dilemma.stdout.strip().splitlines()[-1])
        # Stage S10.5: a lag in the catalogue, the icon web and Why (Valmora's year-on-year mod).
        lag = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/lag_check.gd",
             "--", "--scenario=models/valmora/scenarios/year_on_year.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if lag.returncode != 0:
            print(lag.stdout.strip()[-2000:], lag.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/lag_check.gd failed", file=sys.stderr)
            return 1
        print(lag.stdout.strip().splitlines()[-1])
        # Stage S7.4: Valmora in French, through the start screen and a save.
        language = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/language_check.gd",
             "--", f"--save={folder / 'french.psave'}"],
            capture_output=True, encoding="utf-8", timeout=900)
        if language.returncode != 0:
            print(language.stdout.strip()[-2000:], language.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/language_check.gd failed", file=sys.stderr)
            return 1
        print(language.stdout.strip().splitlines()[-1])
        # Stage S7.1: the start screen, with the example mod chosen.
        start = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/start_screen.gd"],
            capture_output=True, encoding="utf-8", timeout=900)
        if start.returncode != 0:
            print(start.stdout.strip()[-2000:], start.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/start_screen.gd failed", file=sys.stderr)
            return 1
        print(start.stdout.strip().splitlines()[-1])
        # Stage S7.0: a save outlives its model files (another copy of Valmora).
        problem = check_migration(args.godot, folder)
        if problem:
            print(problem, file=sys.stderr)
            return 1
        second = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/second_model.gd",
             "--", "--scenario=models/mini/scenarios/island.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if second.returncode != 0:
            print(second.stdout.strip()[-2000:], second.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/second_model.gd failed", file=sys.stderr)
            return 1
        print(second.stdout.strip().splitlines()[-1])
        # Stage S5.4: a bill voted down by a coalition, through the interface.
        bill = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/bill_vote.gd",
             "--", "--scenario=models/uk/scenarios/hung_parliament.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if bill.returncode != 0:
            print(bill.stdout.strip()[-2000:], bill.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/bill_vote.gd failed", file=sys.stderr)
            return 1
        print(bill.stdout.strip().splitlines()[-1])
        # Stage S6.1: the model's chain from a lever to the poll rating, walked through the popups.
        walk = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/web_walk.gd",
             "--", "--scenario=models/uk/scenarios/2025.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if walk.returncode != 0:
            print(walk.stdout.strip()[-2000:], walk.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/web_walk.gd failed", file=sys.stderr)
            return 1
        print(walk.stdout.strip().splitlines()[-1])
        # Stage S5.5: the politics panel, and losing an election.
        for scenario, expect in (("2025", "office"), ("early_election", "lost")):
            run = subprocess.run(
                [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/politics_check.gd",
                 "--", f"--scenario=models/uk/scenarios/{scenario}.toml", f"--expect={expect}"],
                capture_output=True, encoding="utf-8", timeout=900)
            if run.returncode != 0:
                print(run.stdout.strip()[-2000:], run.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
                print(f"res://tests/politics_check.gd ({expect}) failed", file=sys.stderr)
                return 1
            print(run.stdout.strip().splitlines()[-1])
        # Stage S13.2: the board; political capital. Stage S13.3: looking ahead. Stage S13.4: the people.
        for script in ("res://tests/board_check.gd", "res://tests/capital_check.gd", "res://tests/forecast_check.gd",
                       "res://tests/people_check.gd"):
            run = subprocess.run(
                [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", script,
                 "--", "--scenario=models/uk/scenarios/2025.toml"],
                capture_output=True, encoding="utf-8", timeout=900)
            if run.returncode != 0:
                print(run.stdout.strip()[-2000:], run.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
                print(f"{script} failed", file=sys.stderr)
                return 1
            print(run.stdout.strip().splitlines()[-1])
        # Stage S13.6: the feel: the awaiting state, the month's report, the guide, keys, steady
        # links, formatting, sound; with no script error on the way.
        run = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/feel_check.gd",
             "--", "--scenario=models/uk/scenarios/2025.toml"],
            capture_output=True, encoding="utf-8", timeout=900)
        if run.returncode != 0 or "SCRIPT ERROR" in run.stderr:
            print(run.stdout.strip()[-2000:], run.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/feel_check.gd failed", file=sys.stderr)
            return 1
        print(run.stdout.strip().splitlines()[-1])
        # The UK's budget screen, as the player reads it, against the 2024 public finances.
        dump, breakdowns = folder / "uk_budget.csv", folder / "uk_breakdowns.tsv"
        uk = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/budget_dump.gd",
             "--", "--scenario=models/uk/scenarios/2025.toml", f"--out={dump}", f"--breakdowns={breakdowns}"],
            capture_output=True, encoding="utf-8", timeout=900)
        if uk.returncode != 0 or not dump.exists():
            print(uk.stdout.strip()[-2000:], uk.stderr.strip()[-3000:], sep="\n", file=sys.stderr)
            print("res://tests/budget_dump.gd failed", file=sys.stderr)
            return 1
        problems = compare_uk_budget(dump.read_text(encoding="utf-8"))
        if problems:
            print("\n".join(problems), file=sys.stderr)
            return 1
        print("UK budget screen: every line within 1% of the 2024 public finances")
        problems = check_uk_breakdowns(breakdowns.read_text(encoding="utf-8") if breakdowns.exists() else "", args.runner)
        if problems:
            print("\n".join(problems), file=sys.stderr)
            return 1
        print("UK who gains, who loses: every group shown; a basic rate rise hits the upper deciles, not Scotland;"
              " jobs by industry start at 2024's")
        return 0


def check_migration(godot: str, folder: Path) -> str:
    """Saves a game on a copy of Valmora, changes its files (a new state, a narrower range
    for the basic rate), and loads the save: res://tests/migrate_check.gd checks the rest."""
    copy = folder / "valmora_migrate"
    shutil.copytree(ROOT / "models" / "valmora", copy)
    save = folder / "migrate.psave"
    scenario = copy / "scenarios" / "term.toml"
    for phase in ("save", "load"):
        if phase == "load":
            economy = copy / "economy.toml"
            text = economy.read_text(encoding="utf-8")
            old = '[lever.basic_rate]\nlabel = "Basic income tax rate"\ntype = "real"\nunit = "1"\ndefault = 0.20\nrange = [0, 1]'
            if text.count(old) != 1:
                return "migration check: the basic rate's range is not where expected in Valmora"
            text = text.replace(old, old.replace("range = [0, 1]", "range = [0, 0.25]"))
            text += ('\n[state.months_run]\nlabel = "Months run"\ntype = "int"\nunit = "1"\nphase = "labour"\n'
                     'initial = 0\nnext = "months_run + 1"\n')
            economy.write_text(text, encoding="utf-8", newline="\n")
        run = subprocess.run(
            [godot, "--headless", "--path", str(ROOT / "client"), "--script", "res://tests/migrate_check.gd",
             "--", f"--scenario={scenario}", f"--save={save}", f"--phase={phase}"],
            capture_output=True, encoding="utf-8", timeout=900)
        if run.returncode != 0:
            return "\n".join([run.stdout.strip()[-2000:], run.stderr.strip()[-3000:],
                              f"res://tests/migrate_check.gd ({phase}) failed"])
        print(run.stdout.strip().splitlines()[-1])
    return ""


# Budget screen label -> the 2024 figures (columns of models/uk/data/annual.csv, £ million)
# whose sum it should show; a leading "-" subtracts.
UK_BUDGET = {
    "Income tax": ["income_tax"],
    "National Insurance": ["social_contributions"],
    "Council tax": ["council_tax"],
    "VAT": ["vat"],
    "Corporation tax": ["corporation_tax"],
    "Other taxes on production": ["taxes_on_production", "-vat"],
    "revenue": ["ps_current_receipts"],
    "Public sector pay": ["cg_staff_costs", "lg_staff_costs"],
    "Social benefits": ["ps_social_benefits"],
    "Public purchases": ["cg_procurement", "lg_procurement"],
    "Public investment": ["ps_depreciation", "-ps_net_investment"],
    "Subsidies": ["ps_subsidies"],
    "balance": ["ps_net_borrowing"],
}
UK_INTEREST = ("Debt interest to UK holders", "Debt interest to holders abroad")


def parse_money(text: str) -> float:
    """'£310.70bn' or '−£148.56bn' (with a true minus sign) -> pounds."""
    sign = -1.0 if text.startswith(("-", "\u2212")) else 1.0
    number = text.lstrip("+-\u2212\u2060").lstrip("£").replace(",", "")
    for suffix, size in (("tn", 1e12), ("bn", 1e9), ("m", 1e6)):
        if number.endswith(suffix):
            return sign * float(number[: -len(suffix)]) * size
    return sign * float(number)


def compare_uk_budget(text: str) -> list[str]:
    import csv
    rows = list(csv.DictReader(text.splitlines()))
    shown = {row["label"]: parse_money(row["text"]) for row in rows if not row["label"].startswith("headline ")}
    headline = {row["label"].removeprefix("headline "): row["text"] for row in rows if row["label"].startswith("headline ")}
    with open(ROOT / "models" / "uk" / "data" / "annual.csv", newline="", encoding="utf-8") as handle:
        year = next(row for row in csv.DictReader(handle) if row["period"] == "2024")

    def published(columns):
        return sum((-1 if c.startswith("-") else 1) * float(year[c.lstrip("-")]) for c in columns) * 1e6

    problems = []
    # Stage S9.0: the NHS waiting list shows whole, as the runner has it (on the board since S13.2).
    out = subprocess.run([str(ROOT / "target" / "release" / EXE), "run", str(ROOT / "models" / "uk" / "scenarios" / "2025.toml"),
                          "--steps", "1", "--columns", "waiting_list"], capture_output=True, encoding="utf-8", timeout=600)
    want = int(out.stdout.splitlines()[1]) if out.returncode == 0 else None
    got = headline.get("waiting_list")
    if want is None or got is None or got.replace(",", "") != str(want):
        problems.append(f"UK board: the waiting list shows {got}, the runner has {want}")
    checks = [(label, shown.get(label), published(columns)) for label, columns in UK_BUDGET.items()]
    interest = [shown.get(label) for label in UK_INTEREST]
    checks.append(("Debt interest", None if None in interest else sum(interest), published(["ps_interest"])))
    for label, got, want in checks:
        # Totals are shown to three figures (£1.12tn), so they get the rounding as slack.
        slack = 0.01 if abs(want) < 1e12 else 0.006
        if got is None:
            problems.append(f"UK budget: no line {label!r} on the screen")
        elif abs(got / want - 1) > slack:
            problems.append(f"UK budget: {label} shows {got / 1e9:,.2f}bn, 2024 was {want / 1e9:,.2f}bn")
    return problems


# Breakdown on the "who gains, who loses" panel -> the groups it must show, in order.
UK_GROUPS = {
    "By income decile": ["Poorest tenth", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth",
                         "Richest tenth"],
    "By household type": ["One adult under 65", "One adult 65 or over", "Unrelated adults", "Couple, no children",
                          "Couple, one or two children", "Couple, three or more children", "Couple with grown-up children",
                          "Lone parent", "Lone parent with grown-up children", "Two or more families"],
    "By region": ["North East", "North West", "Yorkshire and The Humber", "East Midlands", "West Midlands",
                  "East of England", "London", "South East", "South West", "Wales", "Scotland", "Northern Ireland"],
}
# Stage S6.4: jobs and pay by industry, each with its own national line.
UK_INDUSTRIES = ["Agriculture, forestry and fishing", "Mining, energy, water and waste", "Manufacturing",
                 "Construction", "Wholesale and retail trade", "Transport and storage", "Accommodation and food",
                 "Information and communication", "Finance and insurance", "Real estate",
                 "Professional and support services", "Public administration and defence", "Education",
                 "Health and social work", "Arts, recreation and other services"]
UK_INDUSTRY_BREAKDOWNS = {"Jobs, by industry": "Workforce jobs",
                          "Pay per employee job, by industry": "Pay per employee job"}
# Stage S8.1: service levels and spending by function.
UK_FUNCTIONS = ["Health", "Education", "Defence", "Police, courts and prisons", "Transport", "Social care",
                "Environment and housing", "Culture, sport and recreation", "Government and the economy"]
UK_FUNCTION_BREAKDOWNS = {"Service level, by function": "Service level, all public services",
                          "Spending, by function": "Public services"}


def check_uk_breakdowns(text: str, runner: Path) -> list[str]:
    """The panel after month 1, and after month 2 with the basic rate (rest of the UK) one
    point higher: every group shown; the all-households line equal to the runner's average;
    the rise taking most from the upper deciles and nothing from Scotland."""
    import csv
    rows = list(csv.DictReader(text.splitlines(), delimiter="\t"))
    problems = []
    for month in ("1", "2"):
        expected = {b: g + ["All households"] for b, g in UK_GROUPS.items()}
        expected.update({b: UK_INDUSTRIES + [total] for b, total in UK_INDUSTRY_BREAKDOWNS.items()})
        expected.update({b: UK_FUNCTIONS + [total] for b, total in UK_FUNCTION_BREAKDOWNS.items()})
        for breakdown, groups in expected.items():
            shown = [r["group"] for r in rows if r["month"] == month and r["breakdown"] == breakdown]
            if shown != groups:
                problems.append(f"UK breakdowns: month {month}, {breakdown} shows {shown}")
    if problems:
        return problems
    line = {(r["month"], r["breakdown"], r["group"]): r for r in rows}
    out = subprocess.run([str(runner), "run", str(ROOT / "models" / "uk" / "scenarios" / "2025.toml"), "--steps", "1",
                          "--columns", "net_income_average"], capture_output=True, encoding="utf-8", timeout=600)
    average = float(out.stdout.splitlines()[1]) * 12 / 100  # pence a month to pounds a year
    shown = parse_money(line[("1", "By region", "All households")]["now"])
    if abs(shown - average) > 0.5:
        problems.append(f"UK breakdowns: all households show £{shown:,.0f} a year, the runner £{average:,.2f}")

    def change(breakdown: str, group: str) -> float:
        return parse_money(line[("2", breakdown, group)]["change"])

    deciles = [change("By income decile", g) for g in UK_GROUPS["By income decile"]]
    # The fifth decile up loses; each of the top three loses £100 a year more than the poorest.
    if not all(d < 0 for d in deciles[4:]) or not all(d < deciles[0] - 100 for d in deciles[7:]):
        problems.append(f"UK breakdowns: a basic rate rise should take most from the upper deciles: {deciles}")
    regions = {g: change("By region", g) for g in UK_GROUPS["By region"]}
    if not regions["Scotland"] > 0 or any(v >= 0 for g, v in regions.items() if g != "Scotland"):
        problems.append(f"UK breakdowns: the rise should fall on every region but Scotland: {regions}")
    if not change("By income decile", "All households") < 0:
        problems.append("UK breakdowns: average net income should fall")
    problems += check_uk_industries(line, runner)
    # Every service at 100% of its first month, after the first month.
    for group in UK_FUNCTIONS + ["Service level, all public services"]:
        shown = line[("1", "Service level, by function", group)]["now"]
        if shown != "100.0%":
            problems.append(f"UK service levels: {group} shows {shown} in the first month")
    return problems


def check_uk_industries(line: dict, runner: Path) -> list[str]:
    """Jobs by industry in the first month are 2024's (ONS JOBS02), and so is their total;
    pay per employee job is the runner's; after the tax rise the jobs move from the
    industries households buy from (accommodation and food) to public services (health)."""
    import csv
    problems = []
    with open(ROOT / "models" / "uk" / "data" / "industry_jobs.csv", newline="", encoding="utf-8") as handle:
        jobs = [float(r["workforce_jobs"]) * 1000 for r in csv.DictReader(handle)]
    for group, want in zip(UK_INDUSTRIES + ["Workforce jobs"], jobs + [sum(jobs)]):
        shown = parse_money(line[("1", "Jobs, by industry", group)]["now"])
        if abs(shown - want) > 0.5:  # shown to the person
            problems.append(f"UK jobs by industry: {group} shows {shown:,.0f}, 2024 had {want:,.0f}")
    out = subprocess.run([str(runner), "run", str(ROOT / "models" / "uk" / "scenarios" / "2025.toml"), "--steps", "1",
                          "--columns", "pay_per_employee_job"], capture_output=True, encoding="utf-8", timeout=600)
    pay = float(out.stdout.splitlines()[1]) * 12 / 100
    shown = parse_money(line[("1", "Pay per employee job, by industry", "Pay per employee job")]["now"])
    if abs(shown - pay) > 0.5:
        problems.append(f"UK pay by industry: all industries show £{shown:,.0f} a year, the runner £{pay:,.2f}")

    def percent(group: str) -> float:
        return float(line[("2", "Jobs, by industry", group)]["percent"].replace("\u2212", "-").replace("\u2060", "").rstrip("%"))
    if not percent("Accommodation and food") < 0 < percent("Health and social work"):
        problems.append("UK jobs by industry: after a tax rise, jobs should move from accommodation and food to health")
    return problems


if __name__ == "__main__":
    raise SystemExit(main())
