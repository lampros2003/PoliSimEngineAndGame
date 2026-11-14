"""The NHS waiting list (stage S9.0).

    python tools/uk/nhs.py       extract models/uk/data/nhs_rtt.csv

Reads NHS England's referral-to-treatment overview time series (Open Government
Licence v3.0), which `python tools/uk/pipeline.py fetch nhs_rtt` downloads, and writes the
month of the series: the number waiting (incomplete pathways, with NHS England's estimates
for trusts that did not report), the new pathways that joined the list (referrals) and the
pathways completed by treatment, admitted and not. The model uses 2024's months, December
2023 and the longest list on record.

The model's waiting list is a stock. Each month referrals join it, in proportion to the
population weighted by its need for health care (S8.1); treatments leave it, following real
health spending; and a share leaves for other reasons (validation, treatment elsewhere,
patients who no longer need it), which the data give as the gap between the flows and the
change in the list.
"""

from __future__ import annotations

import csv
import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "nhs_rtt.csv"
YEAR = 2024
# Columns of the "Full Time Series" sheet (0-based): the month, the number waiting with
# estimates for missing data, completed admitted and non-admitted pathways and new
# pathways, each with estimates for missing data.
MONTH, WAITING, ADMITTED, NON_ADMITTED, NEW = 2, 21, 29, 35, 37
HEADINGS = {WAITING: "Total waiting (mil) with estimates for missing data",
            ADMITTED: "No. of pathways (all) with estimates for missing data",
            NON_ADMITTED: "No. of pathways (all) with estimates for missing data",
            NEW: "No. of new RTT periods with estimates for missing data"}

# How treatments follow real health spending: 1 means a 10% rise in real spending treats 10%
# more patients. A judgement: elective care's share of a change in funding may be more or less
# than its share of the budget, depending on what a government protects.
CAPACITY_RESPONSE = {"low": 0.5, "central": 1.0, "high": 1.5}


def extract() -> list[dict]:
    """Writes every month of the series with its number waiting (blank flows where the series
    has none), and returns the rows."""
    import openpyxl
    wb = openpyxl.load_workbook(CACHE / "nhs_rtt.xlsx", read_only=True, data_only=True)
    rows = list(wb["Full Time Series"].iter_rows(values_only=True))
    heading = next(i for i, r in enumerate(rows) if r and len(r) > NEW and r[WAITING] == HEADINGS[WAITING])
    for column, text in HEADINGS.items():
        if rows[heading][column] != text:
            raise SystemExit(f"nhs: column {column} is {rows[heading][column]!r}, expected {text!r}")

    def count(cell) -> str:
        return str(int(cell)) if isinstance(cell, (int, float)) else ""

    out = []
    for r in rows[heading + 1:]:
        month = r[MONTH]
        if isinstance(month, str) and month.startswith("*"):  # a revised month, written "* Feb-24"
            month = datetime.datetime.strptime(month[1:].strip(), "%b-%y")
        if not isinstance(month, datetime.datetime) or not isinstance(r[WAITING], (int, float)):
            continue
        treated = (count(r[ADMITTED]) and count(r[NON_ADMITTED])
                   and str(int(r[ADMITTED]) + int(r[NON_ADMITTED])))
        out.append({"month": f"{month.year}-{month.month:02d}", "waiting": count(r[WAITING]),
                    "referrals": count(r[NEW]), "treated": treated})
    wanted = [f"{YEAR - 1}-12"] + [f"{YEAR}-{m:02d}" for m in range(1, 13)]
    have = {o["month"]: o for o in out}
    missing = [w for w in wanted if w not in have or not all(have[w].values())]
    if missing:
        raise SystemExit(f"nhs: months missing from the series: {missing}")
    lines = ["month,waiting,referrals,treated"] + [f"{o['month']},{o['waiting']},{o['referrals']},{o['treated']}"
                                                   for o in out]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return out


def table() -> list[dict]:
    with open(OUT, newline="", encoding="utf-8") as handle:
        return [{"month": r["month"], **{k: int(r[k]) if r[k] else None for k in ("waiting", "referrals", "treated")}}
                for r in csv.DictReader(handle)]


def base() -> dict[str, float]:
    """2024's monthly flows, the list at the end of it, and the longest list on record."""
    every = table()
    by_month = {m["month"]: m for m in every}
    t = [by_month[f"{YEAR - 1}-12"]] + [by_month[f"{YEAR}-{m:02d}"] for m in range(1, 13)]
    months = t[1:]
    referrals = sum(m["referrals"] for m in months) / 12
    treated = sum(m["treated"] for m in months) / 12
    change = (t[-1]["waiting"] - t[0]["waiting"]) / 12
    average = sum(m["waiting"] for m in months) / 12
    # What left the list other than by treatment, a month, as a share of the list.
    removal = (referrals - treated - change) / average
    record = max(every, key=lambda m: m["waiting"])
    return {"waiting": t[-1]["waiting"], "referrals": referrals, "treated": treated, "removal": removal,
            "change": change, "record": record["waiting"], "record_month": record["month"]}


def write() -> str:
    """Returns nhs.toml's text."""
    b = base()
    return rules(b["waiting"], b["referrals"], b["treated"], b["removal"], b["record"], b["record_month"])


def rules(waiting: int, referrals: float, treated: float, removal: float, record: int, record_month: str) -> str:
    r = CAPACITY_RESPONSE
    record_month = datetime.datetime.strptime(record_month, "%Y-%m").strftime("%B %Y")
    return f"""# The NHS waiting list (stage S9.0). GENERATED by tools/uk/calibrate.py from
# tools/uk/nhs.py and models/uk/data/nhs_rtt.csv (NHS England, referral-to-treatment
# waiting times, 2024); do not edit.
#
# People waiting for planned hospital treatment in England. Each month referrals join the
# list, growing with the population's need for health care; treatments leave it, following
# real health spending; and a share leaves for other reasons, as it did in 2024.

[param.waiting_list_2024]
doc = "People waiting for treatment in England at the end of 2024"
type = "int"
unit = "person"
value = {waiting}

[param.record_waiting_list]
doc = "The longest the list has been, in {record_month} (NHS England's series from 2007)"
type = "int"
unit = "person"
value = {record}

[param.referrals_2024]
doc = "New referrals for treatment a month in 2024, in England"
type = "real"
unit = "person/month"
value = {referrals!r}

[param.treatments_2024]
doc = "Treatments that ended a wait, a month in 2024, in England"
type = "real"
unit = "person/month"
value = {treated!r}

[param.waiting_removal_rate]
doc = "The share of the list that leaves it each month for reasons other than treatment, as in 2024"
type = "real"
unit = "1/month"
value = {removal!r}

[param.treatment_response]
doc = "How treatments follow real health spending: 1 means 10% more real spending treats 10% more patients (a judgement)"
type = "real"
unit = "1"
low = {r["low"]!r}
central = {r["central"]!r}
high = {r["high"]!r}

[var.health_spending_ratio]
doc = "Real health spending against the first month, as the service has adjusted to it"
type = "real"
unit = "1"
phase = "accounts"
expr = "service_level[function: health] * health_need / people_served_first[function: health]"

[var.referrals]
label = "Referrals for treatment"
doc = "People referred for planned hospital treatment in England this month; more as the population ages"
type = "real"
unit = "person/month"
phase = "accounts"
expr = "referrals_2024 * health_need / people_served_first[function: health]"

[var.treatments]
label = "Treatments"
doc = "Waits that ended in treatment this month, in England; they follow real health spending, cuts biting harder than rises help"
type = "real"
unit = "person/month"
phase = "accounts"
expr = "max(0.0, treatments_2024 * curve(health_spending_ratio, treatment_curve))"

# Stage S11.3: how treatments follow real health spending, a judgement (docs/S11-PLAN.md).
# At 2024's spending (1.0) treatments are 2024's. A rise of up to a fifth adds treatment_response
# times as much (the straight line of S9.0), a further rise to half as much again three fifths
# of that, and beyond, three tenths: a service cannot turn money into treatment at once. A cut
# bites a fifth harder, down to nothing at no spending. Level beyond twice 2024's spending.
[table.treatment_curve]
kind = "curve"
x_unit = "1"
unit = "1"
points = [{{ x = 0.0, y = 0.0 }}, {{ x = 0.5, y = "1.0 - 0.6 * treatment_response" }}, {{ x = 1.0, y = 1.0 }},
          {{ x = 1.2, y = "1.0 + 0.2 * treatment_response" }}, {{ x = 1.5, y = "1.0 + 0.38 * treatment_response" }},
          {{ x = 2.0, y = "1.0 + 0.53 * treatment_response" }}]

[state.waiting_list]
label = "NHS waiting list"
doc = "People waiting for planned hospital treatment in England (NHS England's referral-to-treatment measure)"
type = "int"
unit = "person"
phase = "accounts"
initial = {waiting}
next = "max(0, round(waiting_list + times_step(referrals - treatments - waiting_removal_rate * waiting_list)))"

[var.waiting_months]
label = "Months to clear the waiting list"
doc = "The waiting list over this month's treatments: how long the list would take to clear with no new referrals"
type = "real"
unit = "month"
phase = "accounts"
expr = "safe_div(waiting_list, treatments, 0.0)"
"""


if __name__ == "__main__":
    rows = extract()
    print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} months; 2024 base {base()}")
