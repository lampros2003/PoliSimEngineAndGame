"""The UK's jobs by industry (stage S6.4).

    python tools/uk/jobs.py            extract models/uk/data/industry_jobs.csv

Reads ONS's JOBS02, "Workforce jobs by industry (SIC 2007)", seasonally adjusted (Open
Government Licence v3.0), which `python tools/uk/pipeline.py fetch workforce_jobs`
downloads (an .xls workbook: reading it needs the xlrd package), and writes the 2024
average of the four quarters, in thousands, for the model's 15 industries: workforce jobs
(employee jobs, self-employment jobs, HM Forces and government-supported trainees) and
employee jobs.

`write()` gives the industries block (industries.toml, from tools/uk/template) its jobs:
each industry's share of workforce jobs and the employees' share of its jobs, and the
workforce jobs per person in work, so that in the base month every industry has its 2024
jobs. After that an industry's share of jobs moves with its output against the others'.
"""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "industry_jobs.csv"
# The model's industries (tools/uk/industries.py) by SIC 2007 section.
SECTIONS = {
    "agriculture": "A", "energy_water": "BDE", "manufacturing": "C", "construction": "F", "trade": "G",
    "transport": "H", "hospitality": "I", "information": "J", "finance": "K", "real_estate": "L",
    "business_services": "MN", "public_administration": "O", "education": "P", "health": "Q",
    "other_services": "RST",
}
QUARTERS = ("Mar 24", "Jun 24", "Sep 24", "Dec 24")
# How far an industry's jobs follow its output. Output per worker grows faster where
# output grows faster (Verdoorn's law): estimates of the Verdoorn coefficient, the rise in
# productivity per point of output growth, cluster around a half (McCombie and Thirlwall's
# surveys), which leaves a half for jobs. Low and high presets span 0.3 to 0.7.
ELASTICITY = {"low": 0.3, "central": 0.5, "high": 0.7}


def extract() -> dict[str, tuple[float, float]]:
    import xlrd
    book = xlrd.open_workbook(str(CACHE / "workforce_jobs.xls"))

    def year(sheet: str) -> dict[str, float]:
        s = book.sheet_by_name(sheet)
        codes = [str(s.cell_value(4, c)).strip() for c in range(s.ncols)]
        if codes[2] != "A" or "A-T" not in codes:
            raise SystemExit(f"{sheet}: the SIC sections are not where expected: {codes}")
        rows = [r for r in range(s.nrows) if str(s.cell_value(r, 0)).strip() in QUARTERS]
        if len(rows) != 4:
            raise SystemExit(f"{sheet}: found {len(rows)} quarters of 2024")
        out = {codes[c]: sum(float(s.cell_value(r, c)) for r in rows) / 4 for c in range(2, s.ncols) if codes[c]}
        sections = sum(out[c] for group in SECTIONS.values() for c in group)
        if abs(sections - out["A-T"]) > 2.0:  # the sections are rounded to thousands
            raise SystemExit(f"{sheet}: the sections add to {sections}, the total is {out['A-T']}")
        return out

    jobs, employees = year("WFJ SA"), year("EJ SA")
    out = {n: (sum(jobs[c] for c in g), sum(employees[c] for c in g)) for n, g in SECTIONS.items()}
    lines = ["industry,workforce_jobs,employee_jobs"] + [f"{n},{w!r},{e!r}" for n, (w, e) in out.items()]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return out


def table() -> list[dict[str, str]]:
    with open(OUT, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write(out_dir: Path, people_in_work: float) -> dict[str, str]:
    """Writes out_dir/industries/jobs.csv and returns the industries template's fills.
    Each industry's share of jobs is adjusted in the last place so that the shares add to
    exactly 1 in order, so the base month has the 2024 jobs."""
    rows = table()
    total = sum(float(r["workforce_jobs"]) for r in rows)
    shares = [float(r["workforce_jobs"]) / total for r in rows]
    shares[-1] = 1.0 - sum(shares[:-1])
    added = 0.0
    for s in shares:
        added += s
    assert added == 1.0, added
    folder = out_dir / "industries"
    folder.mkdir(parents=True, exist_ok=True)
    lines = ["industry,jobs,employees"] + [
        f"{r['industry']},{s!r},{float(r['employee_jobs']) / float(r['workforce_jobs'])!r}" for r, s in zip(rows, shares)]
    (folder / "jobs.csv").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return {"jobs_per_worker": repr(total * 1000 / people_in_work),
            **{f"jobs_elasticity_{k}": repr(v) for k, v in ELASTICITY.items()}}


if __name__ == "__main__":
    values = extract()
    for name, (w, e) in values.items():
        print(f"{name:22} workforce jobs {w:8,.2f}k  employee jobs {e:8,.2f}k")
    print(f"{'all':22} workforce jobs {sum(w for w, _ in values.values()):8,.2f}k")
