"""Public spending by function (stage S8.0).

    python tools/uk/functions.py       extract models/uk/data/functions.csv

Reads HM Treasury's Public Expenditure Statistical Analyses 2025, chapter 5 (Open
Government Licence v3.0), which `python tools/uk/pipeline.py fetch pesa2025_ch5`
downloads, and writes, for 2024-25 and the model's nine functions, gross current
procurement (table 5.5) and an estimate of pay, £ million.

PESA gives procurement by function, current spending by function (table 5.4) and pay
only in total (table 5.3). Pay by function is estimated as a function's current spending
less its procurement and less the other kinds of spending that belong to it (debt
interest and grants abroad in general public services, subsidies in economic affairs,
grants to persons in social protection), floored at nothing, then scaled so that the
functions' pay adds to PESA's total. What is left out of each function's current spending
this way is mostly income from sales, which PESA nets off and does not split by function.

`write()` gives the model its functions (functions.toml, written by calibrate.py): a lever
per function, in 2024 prices, whose pay and purchases follow its 2024 split; the public
pay bill and purchases the economy reads, as their sums; and each function's demand for
the industries' products.
"""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "functions.csv"

# Model function: (label, help, PESA functions by number, sub-function rows to add or take).
FUNCTIONS = [
    ("health", "Health", "The NHS and other health services: their staff and what they buy", ["7."], []),
    ("education", "Education", "Schools, colleges, universities and the rest of education", ["9."], []),
    ("defence", "Defence", "The armed forces, their equipment and the rest of defence", ["2."], []),
    ("public_order", "Police, courts and prisons", "Public order and safety: the police, fire services, courts and prisons",
     ["3."], []),
    ("transport", "Transport", "Roads, railways and the rest of transport", [], ["of which: transport"]),
    ("social_care", "Social care", "Adult and children's social care and the other services of social protection "
     "(not benefits, which are separate)", ["10."], []),
    ("environment_housing", "Environment and housing", "Waste, pollution and nature; housing and local amenities",
     ["5.", "6."], []),
    ("culture", "Culture, sport and recreation", "Museums, libraries, sport, broadcasting and the arts", ["8."], []),
    ("general", "Government and the economy", "Running government, foreign affairs, and support for business, "
     "science, jobs and farming", ["1.", "4."], ["-of which: transport"]),
]
# The products each function buys, as a starting point that the input-output tables'
# government purchases then scale (a judgement: only products the government buys). Every
# function also buys some public administration, which takes up what PESA's functions
# spend beyond the tables' purchases of their own products.
SEED = {
    "health": {"health": 0.9, "public_administration": 0.1},
    "social_care": {"health": 0.9, "public_administration": 0.1},
    "education": {"education": 0.7, "public_administration": 0.3},
    "defence": {"public_administration": 0.7, "manufacturing": 0.3},
    "public_order": {"public_administration": 1.0},
    "transport": {"transport": 0.5, "public_administration": 0.5},
    "environment_housing": {"energy_water": 0.5, "public_administration": 0.5},
    "culture": {"other_services": 0.7, "public_administration": 0.3},
    "general": {"public_administration": 0.8, "information": 0.2},
}


def extract() -> dict[str, tuple[float, float]]:
    import openpyxl
    wb = openpyxl.load_workbook(CACHE / "pesa2025_ch5.xlsx", read_only=True, data_only=True)

    def table(sheet: str, stop: str | None = None) -> dict[str, float]:
        """Row label -> 2024-25 outturn, £ million, up to the row starting `stop`."""
        rows = list(wb[sheet].iter_rows(values_only=True))
        header = next(i for i, r in enumerate(rows) if r and "2024-25" in [str(c).strip() for c in r if c])
        column = [str(c).strip() if c is not None else "" for c in rows[header]].index("2024-25")
        out = {}
        for r in rows[header + 2:]:
            label = next((str(c).strip() for c in r[:2] if isinstance(c, str) and c.strip()), "") if r else ""
            if stop and label.startswith(stop):
                break
            if label and isinstance(r[column], (int, float)):
                out.setdefault(label, float(r[column]))
            elif label and isinstance(r[column], str) and r[column].strip().lstrip("-").isdigit():
                out.setdefault(label, float(r[column]))
        return out

    current = table("5_4", "Total public sector current expenditure")
    procurement = table("5_5")
    categories = table("5_3", "Total public sector current expenditure")

    def by_number(values: dict[str, float], number: str) -> float:
        found = [v for k, v in values.items() if k.startswith(number + " ")]
        if len(found) != 1:
            raise SystemExit(f"PESA: function {number} found {len(found)} times")
        return found[0]

    def sub(values: dict[str, float], label: str) -> float:
        found = [v for k, v in values.items() if k.startswith(label)]
        if len(found) != 1:
            raise SystemExit(f"PESA: {label!r} found {len(found)} times")
        return found[0]

    # Spending in a function that is not pay or procurement (see the module's help).
    other = {
        "1.": sub(current, "of which: public sector debt interest") + sub(categories, "Current grants abroad"),
        "4.": sub(categories, "Subsidies to private sector companies") + sub(categories, "Subsidies to public corporations"),
        "10.": sub(categories, "Current grants to persons"),
    }
    raw = {}
    for name, _, _, numbers, subs in FUNCTIONS:
        cur = sum(by_number(current, n) - other.get(n, 0.0) for n in numbers)
        proc = sum(by_number(procurement, n) for n in numbers)
        for s in subs:
            sign = -1.0 if s.startswith("-") else 1.0
            label = s.lstrip("-")
            cur += sign * sub(current, label)
            proc += sign * sub(procurement, label)
        raw[name] = (max(cur - proc, 0.0), proc)
    pay_total = sub(categories, "Pay")
    scale = pay_total / sum(p for p, _ in raw.values())
    out = {name: (pay * scale, proc) for name, (pay, proc) in raw.items()}
    total_proc = sum(proc for _, proc in out.values())
    if abs(total_proc - sub(procurement, "Total public sector gross current procurement")) > 1.0:
        raise SystemExit(f"PESA: the functions' procurement adds to {total_proc}")
    lines = ["function,pay,procurement"] + [f"{n},{p!r},{q!r}" for n, (p, q) in out.items()]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return out


def table() -> dict[str, tuple[float, float]]:
    with open(OUT, newline="", encoding="utf-8") as handle:
        return {r["function"]: (float(r["pay"]), float(r["procurement"])) for r in csv.DictReader(handle)}


def split(total: int, weights: list[float]) -> list[int]:
    """Whole pounds in proportion to `weights`, adding exactly to `total`."""
    parts = [round(total * w / sum(weights)) for w in weights]
    parts[-1] = total - sum(parts[:-1])
    return parts


def rake(seed: dict[str, dict[str, float]], rows: dict[str, float], columns: dict[str, float]) -> dict:
    """Iterative proportional fitting of the seed to row and column sums."""
    x = {f: {p: v for p, v in ps.items() if columns.get(p, 0.0) > 0.0} for f, ps in seed.items()}
    for _ in range(10_000):
        for f, ps in x.items():
            s = sum(ps.values())
            for p in ps:
                ps[p] *= rows[f] / s
        worst = 0.0
        for p, target in columns.items():
            if target <= 0.0:
                continue
            s = sum(ps.get(p, 0.0) for ps in x.values())
            worst = max(worst, abs(s / target - 1.0))
            for ps in x.values():
                if p in ps:
                    ps[p] *= target / s
        if worst < 1e-13:
            return x
    raise SystemExit("functions: the products' rake did not converge")


def write(out_dir: Path, pay_monthly: int, procurement_monthly: int, government_products: dict[str, float]) -> str:
    """Writes out_dir/functions/*.csv and returns functions.toml's text. `pay_monthly` and
    `procurement_monthly` are the model's 2024 public pay bill and purchases, whole pounds a
    month; `government_products` the industries block's domestic product per pound of
    government spending."""
    data = table()
    names = [f[0] for f in FUNCTIONS]
    pay = split(pay_monthly, [data[n][0] for n in names])
    proc = split(procurement_monthly, [data[n][1] for n in names])
    spend = [a + b for a, b in zip(pay, proc)]
    folder = out_dir / "functions"
    folder.mkdir(parents=True, exist_ok=True)
    lines = ["function,pay,spending"] + [f"{n},{a},{s}" for n, a, s in zip(names, pay, spend)]
    (folder / "split.csv").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    # Product shares per pound of each function's spending: every function buys the same
    # domestic share as government purchases as a whole, and together they buy the tables'
    # mix.
    domestic = sum(government_products.values())
    total = float(sum(spend))
    raked = rake(SEED, {n: s / total * domestic for n, s in zip(names, spend)}, government_products)
    lines = ["function,product,value"]
    for n, s in zip(names, spend):
        for p in government_products:
            lines.append(f"{n},{p},{raked[n].get(p, 0.0) * total / s!r}")
    (folder / "products.csv").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return rules(pay, spend)


def rules(pay: list[int], spend: list[int]) -> str:
    names = ", ".join(f'"{f[0]}"' for f in FUNCTIONS)
    labels = ", ".join(f'"{f[1]}"' for f in FUNCTIONS)
    levers = ""
    for (name, label, doc, _, _), s in zip(FUNCTIONS, spend):
        levers += f'''
[lever.spending_{name}]
label = "{label}"
group = "Public services"
type = "money"
unit = "GBP/month"
default = {s}
range = [0, {2 * s}]
leaning = "left"
doc = "{doc}, in 2024 prices; its pay and purchases keep their 2024 split (HM Treasury, PESA 2025)"
'''
    pay_terms = " + ".join(f"muldiv(spending_{f[0]}, function_pay[function: {k}], function_spending[function: {k}])"
                           for k, f in enumerate(FUNCTIONS))
    total_terms = " + ".join(f"spending_{f[0]}" for f in FUNCTIONS)
    chain = "spending_" + FUNCTIONS[-1][0]
    for k in range(len(FUNCTIONS) - 2, -1, -1):
        chain = f"select(coord(function) == {k}, spending_{FUNCTIONS[k][0]}, {chain})"
    return f'''# Public spending by function (stage S8.0). GENERATED by tools/uk/calibrate.py from
# tools/uk/functions.py and models/uk/data/functions.csv (HM Treasury, PESA 2025); do not
# edit.
#
# A lever per function, in 2024 prices. Each function's pay and purchases keep their 2024
# split, and the economy reads their sums, the public pay bill and purchases, as before.

[dim.function]
members = [{names}]
labels = [{labels}]

[param.function_pay]
doc = "Each function's pay bill, 2024, a month"
type = "money"
unit = "GBP/month"
dims = ["function"]
data = "functions/split.csv"
column = "pay"

[param.function_spending]
doc = "Each function's pay and purchases, 2024, a month"
type = "money"
unit = "GBP/month"
dims = ["function"]
data = "functions/split.csv"
column = "spending"

[param.function_products]
doc = "Domestic product bought per pound of each function's spending"
type = "real"
unit = "1"
dims = ["function", "product"]
data = "functions/products.csv"
{levers}
[var.public_pay_bill]
label = "Public sector pay bill (2024 prices)"
type = "money"
unit = "GBP/month"
phase = "labour"
doc = "The functions' pay, each at its 2024 share of the function's spending"
expr = "{pay_terms}"

[var.procurement_bill]
label = "Purchases of goods and services (2024 prices)"
type = "money"
unit = "GBP/month"
phase = "labour"
doc = "The functions' spending other than pay"
expr = "{total_terms} - public_pay_bill"

[var.spending_by_function]
label = "Spending, by function"
doc = "Each function's pay and purchases, at this month's prices"
type = "real"
unit = "GBP/month"
phase = "accounts"
dims = ["function"]
expr = "{chain} * trend_index"

[var.government_demand]
label = "Government demand for UK products"
type = "real"
unit = "GBP/month"
phase = "accounts"
dims = ["product"]
expr = "sum(spending_by_function * function_products, function)"
'''


if __name__ == "__main__":
    values = extract()
    for name, (pay, proc) in values.items():
        print(f"{name:20} pay {pay:9,.0f}  procurement {proc:9,.0f}  (£m, 2024-25)")
