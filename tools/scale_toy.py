"""Make a copy of the toy model with more household records, for timing the engine.

    python tools/scale_toy.py 100000 /tmp/toy-100k

The copy has the same equations and policy. Government purchases, firms' starting money
and the starting value of net sales are scaled with the number of households, so the
larger economy starts near the same steady state. Each record still stands for about a
thousand households, so totals grow with the record count. The data are synthetic.
"""

from __future__ import annotations

import csv
import math
import random
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOY = ROOT / "models" / "toy"
BASE_RECORDS = 1000
SCALED = {  # numbers in the toy model that grow with the size of the economy
    "default = 1_490_000_000": "gov_purchases",
    "initial = 4_300_000_000": "net_sales",
    "initial = 3_440_000_000": "firm_money",
    "range = [0, 10_000_000_000]": "gov_purchases range",
}


def main() -> None:
    records, out = int(sys.argv[1]), Path(sys.argv[2])
    factor = records / BASE_RECORDS
    if out.exists():
        shutil.rmtree(out)
    (out / "data").mkdir(parents=True)
    (out / "scenarios").mkdir()

    for name in ("model.toml", "economy.toml"):
        text = (TOY / name).read_text(encoding="utf-8")
        for old in SCALED:
            if old in text:
                key, _, value = old.partition(" = ")
                if value.startswith("["):
                    text = text.replace(old, f"{key} = [0, {int(10_000_000_000 * factor)}]")
                else:
                    text = text.replace(old, f"{key} = {int(int(value.replace('_', '')) * factor)}")
        (out / name).write_text(text, encoding="utf-8", newline="\n")

    rng = random.Random(20261113)
    with open(out / "data" / "households.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["id", "weight", "wage", "equity_units", "employed0", "money0"])
        for record_id in range(records):
            weight = rng.randint(600, 1400)
            wage = max(900, min(round(rng.lognormvariate(math.log(2400.0), 0.5)), 20000))
            equity = 0 if rng.random() < 0.45 else round((wage / 1000.0) ** 2 * rng.expovariate(1.0) * 10.0)
            employed = 1 if rng.random() < 0.94 else 0
            writer.writerow([record_id, weight, f"{wage}.00", equity, employed, f"{round(wage * 2.45)}.00"])

    (out / "scenarios" / "baseline.toml").write_text(
        '[scenario]\nmodel = ".."\nseed = 20261113\nsteps = 240\npreset = "central"\n', encoding="utf-8", newline="\n")
    print(f"wrote {out} with {records} household records")


if __name__ == "__main__":
    main()
