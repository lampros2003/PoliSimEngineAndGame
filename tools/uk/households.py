"""Synthetic UK households (stage S4.1).

    python tools/uk/households.py            build models/uk/households/ from cached tables

Builds 20,000 household records from published tables only (all ONS, Open Government
Licence v3.0), which `python tools/uk/pipeline.py fetch households2025 ashe3 ashe6`
downloads, together with models/uk/data/population.csv:

- households by type, 2024 (Families and households in the UK, table 7);
- annual gross pay of employees by region and by age group, for men and women, 2024
  (Annual Survey of Hours and Earnings, tables 3.7a and 6.7a: the 10th to 90th
  percentiles);
- people by region, sex and single year of age, mid-2024.

Each record is drawn at random (a fixed seed, so the file is reproducible): a household
type at the published mix, members' ages from the population, employment by an assumed
age profile, employees' pay from ASHE's percentiles for their region and sex, scaled by
their age group, and pensions for those over state pension age. The records are then
weighted by exponential calibration (raking) so that the weighted households match the
published people by region, sex and age band, households by type, and employment.

Writes models/uk/households/households.csv (one row per household, its weight a whole
number of households) and HOUSEHOLDS.md, which lists every target, its published value,
the weighted records' value and the error. Every judgement is in ASSUMPTIONS below.
"""

from __future__ import annotations

import csv
import io
import math
import random
import sys
import zipfile
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
DATA = ROOT / "models" / "uk" / "data"
OUT = ROOT / "models" / "uk" / "households"
SEED = 20241
RECORDS = 20_000

REGIONS = ["north_east", "north_west", "yorkshire", "east_midlands", "west_midlands", "east", "london",
           "south_east", "south_west", "wales", "scotland", "northern_ireland"]
REGION_CODES = ["E12000001", "E12000002", "E12000003", "E12000004", "E12000005", "E12000006", "E12000007",
                "E12000008", "E12000009", "W92000004", "S92000003", "N92000002"]
AGE_BANDS = [(0, 15), (16, 24), (25, 34), (35, 49), (50, 64), (65, 74), (75, 90)]
ASHE_AGES = [(16, 17, "16-17"), (18, 21, "18-21"), (22, 29, "22-29"), (30, 39, "30-39"), (40, 49, "40-49"),
             (50, 59, "50-59"), (60, 90, "60+")]
PERCENTILES = [10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90]

# Judgements the published tables do not settle. Each is a round, documented figure.
ASSUMPTIONS = {
    # Chance of being in work by age (the shape of the Labour Force Survey's rates; the
    # level is then calibrated to total employment).
    "employment_rate": [(16, 17, 0.25), (18, 24, 0.62), (25, 34, 0.84), (35, 49, 0.85), (50, 64, 0.72),
                        (65, 69, 0.24), (70, 90, 0.06)],
    "self_employed_share": 0.13,  # of people in work
    "self_employed_pay_factor": 0.8,  # self-employment income against employees' pay at the same draw
    "lone_parent_female_share": 0.86,
    "state_pension_age": 66,
    "state_pension_full": 221.20 * 52,  # new State Pension, 2024-25, £ a year
    "state_pension_average_share": 0.85,  # of the full rate, across pensioners
    "private_pension_share": 0.6,  # pensioners with an occupational or personal pension
    "private_pension_median": 6_000,  # £ a year
    "pay_tails": (0.4, 2.0),  # pay at the 1st and 99th percentiles, as multiples of the 10th and 90th
    # Above the 99th percentile pay follows a Pareto tail with this index (HMRC's survey of
    # personal incomes puts the UK's top-income index near 2; with the 99th percentile at
    # twice the 90th, the households' National Insurance comes within 2% of the published
    # total, the check that depends on pay alone).
    "pareto_index": 2.0,
    # People outside households (the population estimates include them): care homes and
    # other communal establishments for 75 and over, student halls for 16 to 24. The person
    # targets are then scaled to ONS's count of people in households (table 8).
    "communal_share_75_plus": 0.05,
    "communal_share_16_24": 0.04,
    # Couples without children: half drawn from all adult ages, half from 55 and over
    # (couples whose children have left), which the population's age mix alone undercounts.
    "older_couple_share": 0.5,
}

# Household types: (key, table 7 label, adults, dependent children, adult age ranges)
TYPES = [
    ("one_under_65", "   Under 65", [(18, 64)], (0, 0)),
    ("one_65_plus", "   65 or over", [(65, 90)], (0, 0)),
    ("unrelated_adults", "Two or more unrelated adults", [(18, 40), (18, 40)], (0, 0)),
    ("couple_no_children", "      No children [note 7]", [(20, 90), None], (0, 0)),
    ("couple_one_or_two", "      1 to 2 dependent children", [(22, 58), None], (1, 2)),
    ("couple_three_plus", "      3 or more dependent children", [(25, 55), None], (3, 5)),
    ("couple_grown_children", "      Non-dependent children", [(42, 72), None, (18, 34)], (0, 0)),
    ("lone_parent", "      Dependent children", [(18, 58)], (1, 3)),
    ("lone_parent_grown", "      Non-dependent children", [(40, 78), (18, 34)], (0, 0)),
    ("multi_family", "Multi-family households", [(25, 60), None, (20, 45), None], (1, 2)),
]
# Further adults some households have: (type, age range, how many more: 0 to this)
EXTRA_ADULTS = {"unrelated_adults": ((18, 40), 2), "couple_grown_children": ((18, 34), 1),
                "lone_parent_grown": ((18, 34), 1)}


def load_targets():
    pop = {}
    for r in csv.DictReader((DATA / "population.csv").read_text(encoding="utf-8").splitlines()):
        pop[(r["region"], r["sex"], int(r["age"]))] = int(r["people"])
    wb = openpyxl.load_workbook(CACHE / "households2025.xlsx", read_only=True, data_only=True)
    rows = list(wb["7"].iter_rows(values_only=True))
    header = next(r for r in rows if r and r[0] and str(r[0]).startswith("Number of households"))
    col = list(header).index("2024 Estimate")
    start = rows.index(header)
    counts, seen = {}, {}
    for r in rows[start + 1:]:
        if not r or not r[0]:
            continue
        label = str(r[0])
        seen[label] = seen.get(label, 0) + 1
        # "Non-dependent children" appears twice: couples first, then lone parents.
        for key, want, *_ in TYPES:
            if label.startswith(want) and key not in counts:
                if want.strip().startswith("Non-dependent") and key == "lone_parent_grown" and seen[label] < 2:
                    continue
                if want.strip().startswith("Dependent children") and key == "lone_parent" and label.strip().startswith("Non"):
                    continue
                counts[key] = float(r[col]) * 1000
                break
    if len(counts) != len(TYPES):
        raise SystemExit(f"households table 7: found {sorted(counts)}")
    rows8 = list(wb["8"].iter_rows(values_only=True))
    header8 = next(r for r in rows8 if r and r[0] and str(r[0]).startswith("Number of people"))
    total8 = next(r for r in rows8 if r and r[0] and str(r[0]).startswith("All people in households"))
    people_in_households = float(total8[list(header8).index("2024 Estimate")]) * 1000
    return pop, counts, people_in_households


def load_pay():
    """ASHE 2024 annual gross pay percentiles: by (sex, region) and medians by (sex, age group)."""
    def sheet_rows(zip_name: str, member: str, sheet: str):
        data = zipfile.ZipFile(CACHE / zip_name).read(member)
        wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
        return list(wb[sheet].iter_rows(values_only=True))

    def number(x):
        try:
            return float(str(x).replace(",", ""))
        except (TypeError, ValueError):
            return None

    by_region, by_age = {}, {}
    for sex, sheet in (("male", "Male"), ("female", "Female")):
        rows = sheet_rows("ashe3.zip", "Work Region Occupation SOC20 (2) Table 3.7a   Annual pay - Gross 2024.xlsx", sheet)
        header = [str(c).strip() if c is not None else "" for c in next(r for r in rows if r and r[0] == "Description")]
        cols = {p: header.index(str(p)) for p in PERCENTILES if str(p) in header}
        cols[50] = header.index("Median")
        for region, code in zip(REGIONS, REGION_CODES):
            row = next(r for r in rows if r and r[1] and str(r[1]).strip() == code)
            by_region[(sex, region)] = [number(row[cols[p]]) for p in PERCENTILES]
        rows = sheet_rows("ashe6.zip", "Age Group Table 6.7a   Annual pay - Gross 2024.xlsx", sheet)
        header = [str(c).strip() if c is not None else "" for c in next(r for r in rows if r and r[0] == "Description")]
        median = header.index("Median")
        for lo, hi, label in ASHE_AGES:
            row = next(r for r in rows if r and str(r[0]).strip().rstrip("b").strip() == label)
            by_age[(sex, label)] = number(row[median])
        by_age[(sex, "all")] = number(next(r for r in rows if r and str(r[0]).strip() == "All employees")[median])
    return by_region, by_age


def pay_at(u: float, points: list[float | None]) -> float:
    """Pay at percentile u (0 to 1), log-linear between ASHE's percentiles, with tails."""
    known = [(p / 100, v) for p, v in zip(PERCENTILES, points) if v]
    low_tail, high_tail = ASSUMPTIONS["pay_tails"]
    known = [(0.01, known[0][1] * low_tail)] + known + [(0.99, known[-1][1] * high_tail)]
    if u > 0.99:
        u = min(u, 0.99995)
        return known[-1][1] * (0.01 / (1 - u)) ** (1 / ASSUMPTIONS["pareto_index"])
    u = max(u, 0.01)
    for (p0, v0), (p1, v1) in zip(known, known[1:]):
        if p0 <= u <= p1:
            return math.exp(math.log(v0) + (math.log(v1) - math.log(v0)) * (u - p0) / (p1 - p0))
    return known[-1][1]


def build(rng: random.Random, pop, counts, pay_region, pay_age):
    ages_all = {}
    for (region, sex, age), n in pop.items():
        ages_all[age] = ages_all.get(age, 0) + n
    region_people = {r: sum(n for (rr, _, _), n in pop.items() if rr == r) for r in REGIONS}

    def draw_age(lo, hi):
        ages = list(range(lo, hi + 1))
        return rng.choices(ages, weights=[ages_all[a] for a in ages])[0]

    def employed(age):
        for lo, hi, rate in ASSUMPTIONS["employment_rate"]:
            if lo <= age <= hi:
                return rng.random() < rate
        return False

    def pay(sex, region, age):
        u = rng.random()
        base = pay_at(u, pay_region[(sex, region)])
        label = next(l for lo, hi, l in ASHE_AGES if lo <= age <= hi)
        return base * pay_age[(sex, label)] / pay_age[(sex, "all")]

    type_keys = [t[0] for t in TYPES]
    type_weights = [counts[k] for k in type_keys]
    records = []
    for hid in range(1, RECORDS + 1):
        key = rng.choices(type_keys, weights=type_weights)[0]
        _, _, adult_spec, (kmin, kmax) = next(t for t in TYPES if t[0] == key)
        region = rng.choices(REGIONS, weights=[region_people[r] for r in REGIONS])[0]
        adults = []
        if key == "couple_no_children" and rng.random() < ASSUMPTIONS["older_couple_share"]:
            adult_spec = [(55, 90), None]
        for spec in adult_spec:
            if spec is None:  # a partner: the other sex, about the same age
                head_age, head_sex = adults[-1]
                age = min(90, max(18, head_age + rng.randint(-4, 4)))
                adults.append((age, "female" if head_sex == "male" else "male"))
                continue
            age = draw_age(*spec)
            if key == "lone_parent" or (key == "lone_parent_grown" and not adults):
                sex = "female" if rng.random() < ASSUMPTIONS["lone_parent_female_share"] else "male"
            else:
                sex = rng.choice(["female", "male"])
            adults.append((age, sex))
        if key in EXTRA_ADULTS:
            (lo, hi), most = EXTRA_ADULTS[key]
            for _ in range(rng.randint(0, most)):
                adults.append((draw_age(lo, hi), rng.choice(["female", "male"])))
        children = []
        if kmax:
            youngest_parent = min(a for a, _ in adults[:2])
            for _ in range(rng.randint(kmin, kmax)):
                children.append(rng.randint(0, min(17, max(0, youngest_parent - 18))))
        people = []
        for age, sex in adults:
            work = employed(age)
            self_employed = work and rng.random() < ASSUMPTIONS["self_employed_share"]
            earnings = pay(sex, region, age) if work else 0.0
            if self_employed:
                earnings *= ASSUMPTIONS["self_employed_pay_factor"]
            pension = 0.0
            if age >= ASSUMPTIONS["state_pension_age"]:
                pension = ASSUMPTIONS["state_pension_full"] * ASSUMPTIONS["state_pension_average_share"]
                if rng.random() < ASSUMPTIONS["private_pension_share"]:
                    pension += ASSUMPTIONS["private_pension_median"] * math.exp(rng.gauss(0.0, 0.8))
            people.append({"age": age, "sex": sex, "employee": work and not self_employed,
                           "self_employed": self_employed, "earnings": earnings, "pension": pension})
        for age in children:
            people.append({"age": age, "sex": rng.choice(["female", "male"]), "employee": False,
                           "self_employed": False, "earnings": 0.0, "pension": 0.0})
        records.append({"id": hid, "type": key, "region": region, "adults": len(adults),
                        "children": len(children), "people": people})
    return records


def income_deciles(records, weights) -> dict[int, int]:
    """Each household's decile (1 to 10) of equivalised gross income in the base year, by
    weight: pay and pensions over the modified OECD scale (1 for the first adult, 0.5 for
    each other adult, 0.3 for each child). Ties go by record number."""
    def equivalised(r):
        gross = sum(p["earnings"] + p["pension"] for p in r["people"])
        return gross / (1 + 0.5 * (r["adults"] - 1) + 0.3 * r["children"])

    order = sorted(zip(records, weights), key=lambda rw: (equivalised(rw[0]), rw[0]["id"]))
    total = sum(weights)
    out, below = {}, 0
    for r, w in order:
        out[r["id"]] = min(10, int(below * 10 // total) + 1)
        below += w
    return out


def calibrate(records, targets, households):
    """Exponential (raking) calibration: w = d exp(x.lambda), solved by Newton's method so that
    the weighted totals of every target column equal the target; d spreads the households
    evenly to start. Returns weights and the number of iterations."""
    n, k = len(records), len(targets)
    x = [r["x_solve"] for r in records]  # sparse: {target index: count}
    d = households / n
    def evaluate(lam):
        w = [d * math.exp(min(50.0, sum(lam[j] * v for j, v in xi.items()))) for xi in x]
        totals = [0.0] * k
        for wi, xi in zip(w, x):
            for j, v in xi.items():
                totals[j] += wi * v
        rel = [(t - s) / max(t, 1.0) for (t, _), s in zip(targets, totals)]
        return w, totals, sum(r * r for r in rel), max(abs(r) for r in rel)

    lam = [0.0] * k
    w, totals, size, worst = evaluate(lam)
    for iteration in range(1, 200):
        if worst < 1e-9:
            return w, iteration
        jac = [[0.0] * k for _ in range(k)]
        for wi, xi in zip(w, x):
            items = list(xi.items())
            for j, v in items:
                row = jac[j]
                for j2, v2 in items:
                    row[j2] += wi * v * v2
        gap = [t - s for (t, _), s in zip(targets, totals)]
        step = solve(jac, gap)
        # Damped: at most a factor of e per step, halved until the gap shrinks.
        biggest = max(abs(v) for v in step)
        scale = min(1.0, 1.0 / biggest) if biggest else 1.0
        while True:
            trial = [a + scale * b for a, b in zip(lam, step)]
            w2, totals2, size2, worst2 = evaluate(trial)
            if size2 < size or scale < 1e-6:
                break
            scale /= 2
        lam, w, totals, size, worst = trial, w2, totals2, size2, worst2
    order = sorted(range(k), key=lambda j: -abs(targets[j][0] - totals[j]) / max(targets[j][0], 1.0))
    for j in order[:12]:
        print(f"  {targets[j][1]}: target {targets[j][0]:,.0f}, records {totals[j]:,.0f}", file=sys.stderr)
    raise SystemExit(f"calibration did not converge (largest relative gap {worst:.2e})")


def solve(a, b):
    n = len(b)
    m = [row[:] + [bi] for row, bi in zip(a, b)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        if abs(m[c][c]) < 1e-300:
            raise SystemExit("calibration: a target has no records")
        for r in range(c + 1, n):
            f = m[r][c] / m[c][c]
            if f:
                for j in range(c, n + 1):
                    m[r][j] -= f * m[c][j]
    out = [0.0] * n
    for r in range(n - 1, -1, -1):
        out[r] = (m[r][n] - sum(m[r][j] * out[j] for j in range(r + 1, n))) / m[r][r]
    return out


def main() -> int:
    pop, counts, people_in_households = load_targets()
    pay_region, pay_age = load_pay()
    rng = random.Random(SEED)
    records = build(rng, pop, counts, pay_region, pay_age)

    # Targets: all households; households by type; people by region, sex and age band;
    # people in work.
    targets = [(sum(counts.values()), "households, all")]
    index = {}
    for key, *_ in TYPES:
        index[("type", key)] = len(targets)
        targets.append((counts[key], f"households: {key}"))
    for region in REGIONS:
        for sex in ("female", "male"):
            for lo, hi in AGE_BANDS:
                index[("people", region, sex, lo)] = len(targets)
                total = sum(pop[(region, sex, a)] for a in range(lo, hi + 1))
                if lo >= 75:
                    total *= 1 - ASSUMPTIONS["communal_share_75_plus"]
                if lo == 16:
                    total *= 1 - ASSUMPTIONS["communal_share_16_24"]
                targets.append((float(total), f"people in households: {region} {sex} {lo}-{hi}"))
    people_rows = [j for j, (_, label) in enumerate(targets) if label.startswith("people in households")]
    scale = people_in_households / sum(targets[j][0] for j in people_rows)
    for j in people_rows:
        targets[j] = (targets[j][0] * scale, targets[j][1])
    employment = float(next(r for r in csv.DictReader((DATA / "annual.csv").read_text(encoding="utf-8").splitlines())
                            if r["period"] == "2024")["employment"]) * 1000
    index[("work",)] = len(targets)
    targets.append((employment, "people in work"))
    for r in records:
        x = {0: 1.0, index[("type", r["type"])]: 1.0}
        for p in r["people"]:
            band = next(lo for lo, hi in AGE_BANDS if lo <= p["age"] <= hi)
            j = index[("people", r["region"], p["sex"], band)]
            x[j] = x.get(j, 0.0) + 1.0
            if p["employee"] or p["self_employed"]:
                x[index[("work",)]] = x.get(index[("work",)], 0.0) + 1.0
        # Overlapping targets (all households = the sum of the types) make the system
        # singular; drop the redundant all-households column from the records.
        x.pop(0)
        r["x"] = x
    # Solve without the all-households target (it is the sum of the types): shift indices.
    for r in records:
        r["x_solve"] = {j - 1: v for j, v in r["x"].items()}
    weights, iterations = calibrate(records, targets[1:], targets[0][0])
    whole = [max(1, round(w)) for w in weights]

    # ---- write
    OUT.mkdir(parents=True, exist_ok=True)
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    columns = ["id", "weight", "region_code", "type", "adults", "children", "youngest_child"]
    columns += [f"{f}{i}" for i in range(1, 5) for f in ("age", "sex")]
    columns += [f"{f}{i}" for f in ("earnings", "self_employed", "pension") for i in range(1, 5)]
    columns += ["income_decile"]
    deciles = income_deciles(records, whole)
    writer.writerow(columns)
    for r, w in zip(records, whole):
        adults = [p for p in r["people"]][: r["adults"]]
        kids = [p["age"] for p in r["people"][r["adults"]:]]
        cells = [r["id"], w, REGIONS.index(r["region"]), [t[0] for t in TYPES].index(r["type"]), r["adults"],
                 r["children"], min(kids) if kids else -1]
        if len(adults) > 4:
            raise SystemExit(f"household {r['id']} has more than four adults")
        for i in range(4):
            p = adults[i] if i < len(adults) else None
            cells += [p["age"] if p else -1, (1 if p["sex"] == "male" else 0) if p else -1]
        for field, fmt in (("earnings", "{:.2f}"), ("self_employed", "{}"), ("pension", "{:.2f}")):
            for i in range(4):
                p = adults[i] if i < len(adults) else None
                if field == "self_employed":
                    cells.append(1 if p and p["self_employed"] else 0)
                else:
                    cells.append(fmt.format(p[field]) if p else "0.00")
        cells.append(deciles[r["id"]])
        writer.writerow(cells)
    (OUT / "households.csv").write_text(buffer.getvalue(), encoding="utf-8", newline="\n")

    # ---- report: every target against the whole-number weights
    achieved = [0.0] * len(targets)
    for r, w in zip(records, whole):
        achieved[0] += w
        for j, v in r["x"].items():
            achieved[j] += w * v
    lines = ["# Synthetic UK households", "",
             "Generated by `python tools/uk/households.py`; do not edit. Built from ONS tables (Families and",
             "households 2024, ASHE 2024 tables 3.7a and 6.7a, mid-2024 population estimates), licensed under the",
             "Open Government Licence v3.0. No survey microdata are used.", "",
             f"{RECORDS:,} records; seed {SEED}; calibration converged in {iterations} Newton steps; weights rounded",
             "to whole households, which is the only source of the errors below.", "",
             "## Assumptions", "", *[f"- `{k}`: {v}" for k, v in ASSUMPTIONS.items()], "",
             "## Targets", "", "| Target | Published | Records | Error % |", "|---|---:|---:|---:|"]
    worst = 0.0
    for (t, label), a in zip(targets, achieved):
        err = (a / t - 1) * 100 if t else 0.0
        worst = max(worst, abs(err))
        lines.append(f"| {label} | {t:,.0f} | {a:,.0f} | {err:+.3f} |")
    lines.insert(lines.index("## Assumptions"), f"Largest error: {worst:.3f}%.\n")
    (OUT / "HOUSEHOLDS.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"households.csv: {RECORDS:,} records, {sum(whole):,} households; calibration {iterations} steps; "
          f"largest target error {worst:.3f}%")
    return 0 if worst < 1.0 else 1


if __name__ == "__main__":
    sys.exit(main())
