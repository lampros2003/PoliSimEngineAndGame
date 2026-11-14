"""The UK's industries from the input-output analytical tables (stage S3.6).

    python tools/uk/industries.py          extract from the cached download and check

Reads ONS's 2023 input-output analytical tables (product by product, domestic use at basic
prices, £ million; Open Government Licence v3.0), which `python tools/uk/pipeline.py fetch
iot2023` downloads into .cache/uk/, and aggregates the 104 products into 15 industries by
SIC 2007 section. Writes into models/uk/data/:

- industries.csv: per industry, its label, output, domestic and imported intermediate inputs, taxes
  on products paid on inputs, compensation of employees, gross operating surplus and
  mixed income, other taxes on production, gross value added, and domestic final use by
  households and non-profits, government, investment (fixed capital, inventories,
  valuables) and exports;
- io_domestic.csv: from, to, value: domestic intermediate use of each industry's products
  by each industry;
- io_final_totals.csv: per final use (households, government, investment, exports), the
  total at purchasers' prices, imports and taxes included, and the domestic part at basic
  prices, so that spending can be turned into demand for UK industries' products;

and INDUSTRIES.md with the source, checksum and checks: each industry's output equals its
inputs plus value added, and the sale of its products (intermediate plus final) equals
its output; the industries' value added adds up to the table's total.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data"

# Model industry: (label, SIC 2007 sections)
INDUSTRIES = [
    ("agriculture", "Agriculture, forestry and fishing", "A"),
    ("energy_water", "Mining, energy, water and waste", "BDE"),
    ("manufacturing", "Manufacturing", "C"),
    ("construction", "Construction", "F"),
    ("trade", "Wholesale and retail trade", "G"),
    ("transport", "Transport and storage", "H"),
    ("hospitality", "Accommodation and food", "I"),
    ("information", "Information and communication", "J"),
    ("finance", "Finance and insurance", "K"),
    ("real_estate", "Real estate", "L"),
    ("business_services", "Professional and support services", "MN"),
    ("public_administration", "Public administration and defence", "O"),
    ("education", "Education", "P"),
    ("health", "Health and social work", "Q"),
    ("other_services", "Arts, recreation and other services", "RST"),
]
FINAL = {
    "households": ["P3 S14", "P3 S15"],
    "government": ["P3 S13"],
    "investment": ["P51G", "P52", "P53"],
    "exports": ["P61EU", "P61RW", "P62"],
}
ROWS = {
    "imports": "Use of imported products, cif",
    "product_taxes": "Taxes less subsidies on products",
    "compensation": "D1",
    "operating_surplus": "GOS & MI",
    "production_taxes": "D29-D39",
    "gva": "GVA",
    "output": "P1",
}


def industry_of(code: str) -> str:
    section = code[4]  # CPA_A01 -> A
    for name, _, sections in INDUSTRIES:
        if section in sections:
            return name
    raise KeyError(code)


def main() -> int:
    wb = openpyxl.load_workbook(CACHE / "iot2023.xlsx", read_only=True, data_only=True)
    rows = list(wb["IOT"].iter_rows(values_only=True))
    codes = rows[3]
    product_cols = [i for i, c in enumerate(codes) if isinstance(c, str) and c.startswith("CPA_")]
    col_index = {c: i for i, c in enumerate(codes) if c}
    by_code = {}
    for row in rows[5:]:
        key = row[0] if row[0] else (row[1] or "").strip()
        if key:
            by_code[key] = row
    products = [codes[i] for i in product_cols]
    names = [n for n, _, _ in INDUSTRIES]
    labels = {n: label for n, label, _ in INDUSTRIES}

    def num(x) -> float:
        return float(x) if isinstance(x, (int, float)) else 0.0

    # Domestic intermediate use, aggregated: z[from][to]
    z = {a: {b: 0.0 for b in names} for a in names}
    final = {a: {k: 0.0 for k in FINAL} for a in names}
    for p in products:
        row = by_code[p]
        a = industry_of(p)
        for q, i in zip(products, product_cols):
            z[a][industry_of(q)] += num(row[i])
        for k, cols in FINAL.items():
            final[a][k] += sum(num(row[col_index[c]]) for c in cols)
    primary = {}
    for key, label in ROWS.items():
        row = by_code[label]
        primary[key] = {a: 0.0 for a in names}
        for q, i in zip(products, product_cols):
            primary[key][industry_of(q)] += num(row[i])

    checks, problems = [], 0
    checks.append("## Each industry's inputs, value added and sales add up to its output\n\n"
                  "| Industry | Output | Inputs + value added | Sales | Residuals |\n|---|---:|---:|---:|---:|")
    out_rows = []
    for a in names:
        inputs = sum(z[b][a] for b in names) + primary["imports"][a] + primary["product_taxes"][a] + primary["gva"][a]
        sales = sum(z[a][b] for b in names) + sum(final[a].values())
        output = primary["output"][a]
        r1, r2 = inputs - output, sales - output
        bad = abs(r1) > 1 or abs(r2) > 1
        problems += bad
        checks.append(f"| {a} | {output:,.0f} | {inputs:,.0f} | {sales:,.0f} | {r1:,.1f} / {r2:,.1f} |")
        va = primary["compensation"][a] + primary["operating_surplus"][a] + primary["production_taxes"][a]
        problems += abs(va - primary["gva"][a]) > 1
        out_rows.append([a, labels[a], *(round(v, 3) for v in (
            output, sum(z[b][a] for b in names), primary["imports"][a], primary["product_taxes"][a],
            primary["compensation"][a], primary["operating_surplus"][a], primary["production_taxes"][a],
            primary["gva"][a], final[a]["households"], final[a]["government"], final[a]["investment"],
            final[a]["exports"]))])
    total_gva = sum(primary["gva"].values())
    published = num(by_code["GVA"][col_index["_T"]])
    checks.append(f"\nValue added: industries {total_gva:,.0f}; the table's total {published:,.0f}; "
                  f"difference {total_gva - published:,.1f}.")
    problems += abs(total_gva - published) > 1

    def write(path: Path, header: list[str], data: list[list]) -> None:
        buffer = io.StringIO()
        w = csv.writer(buffer, lineterminator="\n")
        w.writerow(header)
        w.writerows(data)
        path.write_text(buffer.getvalue(), encoding="utf-8", newline="\n")

    write(OUT / "industries.csv",
          ["industry", "label", "output", "domestic_inputs", "imported_inputs", "product_taxes", "compensation",
           "operating_surplus", "production_taxes", "gva", "households", "government", "investment", "exports"],
          out_rows)
    write(OUT / "io_domestic.csv", ["from", "to", "value"],
          [[a, b, round(z[a][b], 3)] for a in names for b in names])
    purchasers = by_code["Total intermediate use at purchaser's prices"]
    write(OUT / "io_final_totals.csv", ["use", "total_purchasers_prices", "domestic_basic_prices"],
          [[k, round(sum(num(purchasers[col_index[c]]) for c in cols), 3), round(sum(final[a][k] for a in names), 3)]
           for k, cols in FINAL.items()])

    data = (CACHE / "iot2023.xlsx").read_bytes()
    meta_path = CACHE / "iot2023.meta.json"
    retrieved = json.loads(meta_path.read_text())["retrieved"] if meta_path.exists() else "unknown"
    text = ["# UK industries", "",
            "Generated by `python tools/uk/industries.py`; do not edit. Source: Office for National Statistics,",
            "UK input-output analytical tables 2023 (product by product), licensed under the Open Government",
            "Licence v3.0.", "",
            f"Cached file `iot2023.xlsx`, retrieved {retrieved}, SHA-256 `{hashlib.sha256(data).hexdigest()[:16]}...`.", "",
            "| Industry | Label | SIC 2007 sections |", "|---|---|---|",
            *[f"| {n} | {label} | {', '.join(s)} |" for n, label, s in INDUSTRIES], "", *checks, ""]
    (OUT / "INDUSTRIES.md").write_text("\n".join(text), encoding="utf-8", newline="\n")
    print(f"industries.csv: {len(out_rows)} industries, value added {total_gva:,.0f}; {problems} check(s) failed")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
