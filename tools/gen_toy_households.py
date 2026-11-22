"""Generate the synthetic household sample for the toy model.

    python tools/gen_toy_households.py

Writes models/toy/data/households.csv. The output is committed, so the generator's own
floating-point behaviour never affects a simulation: the engine only ever reads the CSV. Nothing here is real data; the distributions are invented to look plausible.
"""

from __future__ import annotations

import csv
import math
import random
from pathlib import Path

SEED = 20261113
RECORDS = 1000
OUT = Path(__file__).resolve().parent.parent / "models" / "toy" / "data" / "households.csv"


def main() -> None:
    rng = random.Random(SEED)
    rows = []
    for record_id in range(RECORDS):
        weight = rng.randint(600, 1400)  # real households this record stands for
        wage = round(rng.lognormvariate(math.log(2400.0), 0.5))  # pounds per month when employed
        wage = max(900, min(wage, 20000))
        # Share ownership is concentrated: 45% of households own none, and holdings rise
        # faster than wages among the rest.
        if rng.random() < 0.45:
            equity = 0
        else:
            equity = round((wage / 1000.0) ** 2 * rng.expovariate(1.0) * 10.0)
        employed = 1 if rng.random() < 0.94 else 0
        money = round(wage * 2.45)  # pounds of money held at the start, near its long-run level
        rows.append({"id": record_id, "weight": weight, "wage": f"{wage}.00",
                     "equity_units": equity, "employed0": employed, "money0": f"{money}.00"})

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    households = sum(r["weight"] for r in rows)
    wage_bill = sum(r["weight"] * float(r["wage"]) for r in rows if r["employed0"])
    print(f"wrote {OUT} ({RECORDS} records, {households:,} households)")
    print(f"initial monthly wage bill: {wage_bill:,.0f}")


if __name__ == "__main__":
    main()
