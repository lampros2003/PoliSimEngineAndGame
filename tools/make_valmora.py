"""Build models/valmora from the toy model: the same economy, scaled to an invented
mid-sized country of about eight million households with its own currency.

    python tools/make_valmora.py

Every record stands for eight times as many households, and the national amounts that
must grow with the economy (government purchases, firms' starting cash, last month's
sales) are scaled to match, so Valmora starts in the same steady state as the toy model.
Nothing here describes a real country.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOY = ROOT / "models" / "toy"
OUT = ROOT / "models" / "valmora"
FACTOR = 8
SCALED = {
    "default = 1_490_000_000": f"default = {1_490_000_000 * FACTOR:_}",
    "range = [0, 10_000_000_000]": f"range = [0, {10_000_000_000 * FACTOR:_}]",
    "initial = 4_300_000_000": f"initial = {4_300_000_000 * FACTOR:_}",
    "initial = 3_440_000_000": f"initial = {3_440_000_000 * FACTOR:_}",
}
TERM = '''# A five-year term in Valmora, an invented country of about eight million households.
# The economy is the toy model's, scaled up (tools/make_valmora.py).

[scenario]
model = ".."
seed = 20270101
steps = 60
preset = "central"

# Presentation settings for the game client and `polisim play`. Not part of the run.
[play]
country = "Valmora"
currency_symbol = "Cr"
currency_name = "crowns"
start = "2027-01"
term = 60
government = "government"
headline = ["gdp", "unemployment_rate", "gov_balance", "-gov_money"]
watch = ["gdp", "unemployment_rate", "gov_balance", "consumption_total", "hh_money.total"]

[play.labels]
"-gov_money" = "Public debt"
'''


def main() -> None:
    (OUT / "data").mkdir(parents=True, exist_ok=True)
    (OUT / "scenarios").mkdir(exist_ok=True)
    for name in ("model.toml", "economy.toml"):
        text = (TOY / name).read_text(encoding="utf-8")
        for old, new in SCALED.items():
            text = text.replace(old, new)
        text = text.replace("GBP", "VLC").replace('id = "toy"', 'id = "valmora"')
        text = text.replace('title = "Toy three-sector economy"', 'title = "Valmora"')
        text = text.replace("# Toy three-sector economy:", "# Valmora (an invented country), generated from the toy model by\n# tools/make_valmora.py. The toy model's notes follow.\n#\n# Toy three-sector economy:")
        (OUT / name).write_text(text, encoding="utf-8", newline="\n")
    rows = list(csv.DictReader((TOY / "data" / "households.csv").read_text(encoding="utf-8").splitlines()))
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    for row in rows:
        row["weight"] = str(int(row["weight"]) * FACTOR)
        writer.writerow(row)
    (OUT / "data" / "households.csv").write_text(buffer.getvalue(), encoding="utf-8", newline="\n")
    (OUT / "scenarios" / "term.toml").write_text(TERM, encoding="utf-8", newline="\n")
    households = sum(int(r["weight"]) for r in rows)  # already scaled above
    print(f"wrote {OUT}: {households:,} households")


if __name__ == "__main__":
    main()
