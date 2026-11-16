"""Politics against history (stage S9.4): the voters' reactions fitted to past elections.

    python tools/uk/history.py       extract models/uk/data/elections/history.csv and
                                     write the fit to models/uk/data/elections/HISTORY.md

Reads, from .cache/uk/ (`python tools/uk/pipeline.py fetch ge2010 ge2015 ge2017 ge2019
ge2024 rhdi_regions aps_history`):

- the general elections of 2010, 2015, 2017, 2019 and 2024 by candidate, from UK
  Parliament's election results site (Open Parliament Licence v3.0): the senior governing
  party's votes and the electorate, by region of Great Britain (candidates' names are not
  kept);
- ONS's regional real household disposable income per head (Open Government Licence v3.0),
  for the growth of real income in the year before each election;
- the Annual Population Survey's employment and unemployment by region (ONS via Nomis,
  OGL), in the twelve months before each election.

The model's voters judge the government on the growth of their real income over about a
year, on unemployment in their region and inflation since the last election, and on its
time in office (tools/uk/voters.py). For each of the four terms from 2010 to 2024 and each
of the eleven regions of Great Britain, the change in the log-odds of the senior governing
party's share of the electorate between elections is regressed on the change in income
growth and in unemployment, with an effect for each term that takes up everything national
(inflation, time in office, the parties' fortunes). The regional variation identifies the
income and unemployment effects; the four term effects are too few, and too full of
events, to identify inflation and time in office. Each fitted effect is then combined with
the earlier judgement, each weighted by its precision (the judgement's low and high presets
taken as a standard deviation either side): the data move the judgements as far as they
can bear. The fit on the first three terms is checked on the fourth, 2019 to 2024.
"""

from __future__ import annotations

import csv
import io
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "elections"
ELECTIONS = [2010, 2015, 2017, 2019, 2024]
# The senior party of government at each election from 2015 to 2024 (from 2010 to 2015 in
# coalition with the liberal bloc, whose collapse in 2015 is its own story).
GOVERNING = "Conservative"
# Great Britain's regions, as the sources name them, and as the model does. Northern Ireland
# is left out: the governing party barely stands there.
REGIONS = {
    "North East": "north_east", "North West": "north_west", "Yorkshire and The Humber": "yorkshire",
    "East Midlands": "east_midlands", "West Midlands": "west_midlands", "East of England": "east",
    "London": "london", "South East": "south_east", "South West": "south_west", "Wales": "wales",
    "Scotland": "scotland",
}
# The year or years of real income growth that cover the twelve months before each election.
INCOME_YEARS = {2010: [2010], 2015: [2014, 2015], 2017: [2016, 2017], 2019: [2019], 2024: [2023, 2024]}
# The Annual Population Survey's twelve months before each election.
APS_PERIODS = {"Apr 2009-Mar 2010": 2010, "Apr 2014-Mar 2015": 2015, "Jul 2016-Jun 2017": 2017,
               "Jan 2019-Dec 2019": 2019, "Jul 2023-Jun 2024": 2024}
# Years the governing party had been in office at each election, and whether it was in
# office at the one before: 2010 is the start of its run.
YEARS_IN_OFFICE = {2015: 5.0, 2017: 7.1, 2019: 9.6, 2024: 14.2}


def _region(row: dict) -> str | None:
    name = row["English region name"] if row["Country name"] == "England" else row["Country name"]
    return REGIONS.get(name)


def _votes(year: int) -> dict[str, tuple[int, int]]:
    """Region -> (the governing party's votes, the electorate)."""
    text = (CACHE / f"ge{year}.csv").read_text(encoding="utf-8-sig")
    votes = dict.fromkeys(REGIONS.values(), 0)
    electorate = dict.fromkeys(REGIONS.values(), 0)
    seen: set[str] = set()
    for row in csv.DictReader(io.StringIO(text)):
        region = _region(row)
        if region is None:
            continue
        if row["Main party name"] == GOVERNING:
            votes[region] += int(row["Candidate vote count"])
        code = row["Constituency geographic code"]
        if code not in seen:
            seen.add(code)
            electorate[region] += int(row["Electorate"])
    return {r: (votes[r], electorate[r]) for r in REGIONS.values()}


def _income_growth() -> dict[str, dict[int, float]]:
    """Region -> year -> growth of real household disposable income per head, a share."""
    import openpyxl
    wb = openpyxl.load_workbook(CACHE / "rhdi_regions.xlsx", read_only=True, data_only=True)
    rows = list(wb["Table 8"].iter_rows(values_only=True))
    head = next(r for r in rows if r and r[0] == "ITL")
    if "per head" not in str(rows[0][0]):
        raise SystemExit(f"history: Table 8 is not growth per head: {rows[0][0]!r}")
    years = {i: int(h) for i, h in enumerate(head) if isinstance(h, str) and h.isdigit()}
    out: dict[str, dict[int, float]] = {}
    for r in rows:
        if r and r[0] in ("ITL1", "Country") and r[2] in REGIONS:
            out[REGIONS[r[2]]] = {y: float(r[i]) / 100 for i, y in years.items() if r[i] is not None}
    if set(out) != set(REGIONS.values()):
        raise SystemExit(f"history: regions missing from the income table: {set(REGIONS.values()) - set(out)}")
    return out


def _unemployment() -> dict[int, dict[str, float]]:
    """Election -> region -> unemployment rate."""
    counts: dict[int, dict[str, dict[str, float]]] = {}
    text = (CACHE / "aps_history.csv").read_text(encoding="utf-8-sig")
    for row in csv.DictReader(io.StringIO(text)):
        name = "East of England" if row["GEOGRAPHY_NAME"] == "East" else row["GEOGRAPHY_NAME"]
        if row["DATE_NAME"] in APS_PERIODS and name in REGIONS:
            counts.setdefault(APS_PERIODS[row["DATE_NAME"]], {}).setdefault(REGIONS[name], {})[
                row["C_ECOPUK11_NAME"]] = float(row["OBS_VALUE"])
    return {y: {r: c["Unemployed"] / (c["Employed"] + c["Unemployed"]) for r, c in by.items()}
            for y, by in counts.items()}


def extract() -> list[dict]:
    growth = _income_growth()
    unemployment = _unemployment()
    rows = []
    for year in ELECTIONS:
        votes = _votes(year)
        for region in REGIONS.values():
            g = sum(growth[region][y] for y in INCOME_YEARS[year]) / len(INCOME_YEARS[year])
            rows.append({"election": year, "region": region, "governing_votes": votes[region][0],
                         "electorate": votes[region][1], "income_growth": round(g, 6),
                         "unemployment": round(unemployment[year][region], 6)})
    OUT.mkdir(parents=True, exist_ok=True)
    keys = list(rows[0])
    lines = [",".join(keys)] + [",".join(str(r[k]) for k in keys) for r in rows]
    (OUT / "history.csv").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return rows


def table() -> list[dict]:
    with open(OUT / "history.csv", newline="", encoding="utf-8") as handle:
        return [{k: (v if k == "region" else float(v)) for k, v in r.items()} for r in csv.DictReader(handle)]


# ---------------------------------------------------------------- least squares

def _solve(a: list[list[float]], b: list[float]) -> list[float]:
    """Gaussian elimination with partial pivoting."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * y for x, y in zip(m[r], m[c])]
    return [m[i][n] / m[i][i] for i in range(n)]


def _inverse(a: list[list[float]]) -> list[list[float]]:
    n = len(a)
    columns = [_solve(a, [1.0 if i == j else 0.0 for i in range(n)]) for j in range(n)]
    return [[columns[j][i] for j in range(n)] for i in range(n)]


def ols(x: list[list[float]], y: list[float]) -> tuple[list[float], list[float], float]:
    """Coefficients, their standard errors, and R squared."""
    k = len(x[0])
    xtx = [[sum(r[i] * r[j] for r in x) for j in range(k)] for i in range(k)]
    xty = [sum(r[i] * v for r, v in zip(x, y)) for i in range(k)]
    beta = _solve(xtx, xty)
    resid = [v - sum(b * c for b, c in zip(beta, r)) for r, v in zip(x, y)]
    s2 = sum(e * e for e in resid) / (len(y) - k)
    inv = _inverse(xtx)
    mean = sum(y) / len(y)
    r2 = 1 - sum(e * e for e in resid) / sum((v - mean) ** 2 for v in y)
    return beta, [math.sqrt(s2 * inv[i][i]) for i in range(k)], r2


def _logit(p: float) -> float:
    return math.log(p / (1 - p))


def observations(rows: list[dict]) -> list[dict]:
    """One per term and region: the change in the governing party's log-odds, in income
    growth and in unemployment."""
    at = {(int(r["election"]), r["region"]): r for r in rows}
    out = []
    for before, after in zip(ELECTIONS, ELECTIONS[1:]):
        for region in REGIONS.values():
            a, b = at[(before, region)], at[(after, region)]
            out.append({"term": after, "region": region,
                        "swing": _logit(b["governing_votes"] / b["electorate"])
                        - _logit(a["governing_votes"] / a["electorate"]),
                        "income": b["income_growth"] - a["income_growth"],
                        "unemployment": b["unemployment"] - a["unemployment"]})
    return out


def fit(obs: list[dict], terms: list[int]) -> dict:
    """Term effects, then the income and unemployment effects."""
    use = [o for o in obs if o["term"] in terms]
    x = [[1.0 if o["term"] == t else 0.0 for t in terms] + [o["income"], o["unemployment"]] for o in use]
    beta, se, r2 = ols(x, [o["swing"] for o in use])
    k = len(terms)
    return {"terms": dict(zip(terms, beta[:k])), "income": (beta[k], se[k]),
            "unemployment": (beta[k + 1], se[k + 1]), "r2": r2, "n": len(use)}


def combine(prior: dict, estimate: tuple[float, float]) -> dict:
    """The judgement (central, with low and high a standard deviation either side) and the
    fit (estimate, standard error), weighted by their precisions."""
    sd_prior = (abs(prior["high"] - prior["central"]) + abs(prior["central"] - prior["low"])) / 2
    w_prior, w_fit = 1 / sd_prior ** 2, 1 / estimate[1] ** 2
    mean = (prior["central"] * w_prior + estimate[0] * w_fit) / (w_prior + w_fit)
    sd = 1 / math.sqrt(w_prior + w_fit)
    sign = 1 if prior["central"] > 0 else -1
    # Low is the weaker effect, as for every reaction; never the wrong sign.
    low = sign * max(abs(mean) - sd, abs(mean) / 4)
    return {"low": round(low, 3), "central": round(mean, 3), "high": round(mean + sign * sd, 3), "sd": sd}


# The judgements this replaces where the data allow (tools/uk/voters.py before stage S9.4).
PRIOR = {"income": {"low": 1.25, "central": 2.5, "high": 3.75},
         "unemployment": {"low": -3.0, "central": -6.0, "high": -9.0}}


def results() -> dict:
    """The fit and the combined effects, from the committed history.csv."""
    obs = observations(table())
    terms = ELECTIONS[1:]
    full = fit(obs, terms)
    early = fit(obs, terms[:-1])
    # The fourth term, predicted from the first three: each region's swing against the
    # national one, which the term effect takes up.
    last = [o for o in obs if o["term"] == terms[-1]]
    mean = {k: sum(o[k] for o in last) / len(last) for k in ("swing", "income", "unemployment")}
    predicted = [early["income"][0] * (o["income"] - mean["income"])
                 + early["unemployment"][0] * (o["unemployment"] - mean["unemployment"]) for o in last]
    actual = [o["swing"] - mean["swing"] for o in last]
    mp, ma = sum(predicted) / len(predicted), sum(actual) / len(actual)
    cov = sum((p - mp) * (a - ma) for p, a in zip(predicted, actual))
    corr = cov / math.sqrt(sum((p - mp) ** 2 for p in predicted) * sum((a - ma) ** 2 for a in actual))
    # Time in office from the term effects (no constant): weak, and reported only.
    years = [YEARS_IN_OFFICE[t] - (YEARS_IN_OFFICE.get(prev, 0.0)) for prev, t in zip(ELECTIONS, terms)]
    effects = [full["terms"][t] for t in terms]
    tenure = sum(e * y for e, y in zip(effects, years)) / sum(y * y for y in years)
    resid = [e - tenure * y for e, y in zip(effects, years)]
    tenure_se = math.sqrt(sum(r * r for r in resid) / (len(years) - 1) / sum(y * y for y in years))
    return {"full": full, "early": early, "check_correlation": corr, "tenure": (tenure, tenure_se),
            "income": combine(PRIOR["income"], full["income"]),
            "unemployment": combine(PRIOR["unemployment"], full["unemployment"]), "observations": obs}


def report(res: dict) -> str:
    full, early = res["full"], res["early"]
    rows = "\n".join(f"| {o['term']} | {o['region']} | {o['swing']:+.3f} | {o['income'] * 100:+.1f} | "
                     f"{o['unemployment'] * 100:+.1f} |" for o in res["observations"])
    terms = " ".join(f"{t}: {v:+.2f}," for t, v in full["terms"].items()).rstrip(",")
    inc, un = res["income"], res["unemployment"]
    t_inc = full["income"][0] / full["income"][1]
    t_un = full["unemployment"][0] / full["unemployment"][1]
    income_text = (f"Regions whose real incomes grew faster swung towards the government, by an amount "
                   f"in the range the economic-voting literature finds, but the error is "
                   f"{1 / abs(t_inc):.0%} of the estimate: weak evidence, which moves the judgement a little."
                   if t_inc > 0 else
                   "Faster income growth did not go with swings towards the government here; the "
                   "judgement carries the combined effect.")
    unemployment_text = ("Regional unemployment, which moved much in step across regions, cannot be told "
                         "apart from zero here" if abs(t_un) < 2 else "Regional unemployment matters")
    unemployment_text += (f" (t = {t_un:.1f}), so the combined effect is "
                          f"{abs(un['central'] / PRIOR['unemployment']['central']):.0%} of the earlier judgement.")
    check_text = ("The pattern is predicted, if loosely." if res["check_correlation"] > 0.3 else
                  "So the effects fitted on 2010 to 2019 do not predict 2024's regional pattern: something other "
                  "than these measures of the economy shaped it. The fit is weak evidence, and it moves the "
                  "judgements only by its weight.")
    return f"""# The voters' reactions against past elections (stage S9.4)

Generated by `python tools/uk/history.py` from `history.csv`; do not edit. Sources: UK
Parliament's election results (Open Parliament Licence v3.0), ONS's regional real household
disposable income per head and the Annual Population Survey (Open Government Licence v3.0).
The method is in the tool's docstring.

## Fit

{full['n']} observations: four terms (2010-15, 2015-17, 2017-19, 2019-24) by eleven regions of
Great Britain. The change in the log-odds of the senior governing party's share of the
electorate is regressed on the change in real income growth in the year before each
election and in regional unemployment, with an effect for each term. R squared
{full['r2']:.3f}, nearly all of it the term effects ({terms}).

| Effect, on the governing blocs' utility | Fitted | Standard error | Judgement before | Combined (low / central / high) |
|---|---:|---:|---:|---|
| Income: per unit of real income growth | {full['income'][0]:.2f} | {full['income'][1]:.2f} | {PRIOR['income']['central']} | {inc['low']} / {inc['central']} / {inc['high']} |
| Unemployment: per unit of the regional rate | {full['unemployment'][0]:.2f} | {full['unemployment'][1]:.2f} | {PRIOR['unemployment']['central']} | {un['low']} / {un['central']} / {un['high']} |

{income_text} {unemployment_text} Time in office, from the term effects alone:
{res['tenure'][0]:+.3f} a year (standard error {res['tenure'][1]:.3f}), against a judgement of -0.025: four
terms are too few, and 2017's and 2024's swings too large, to say more, so it and
inflation's effect are left as they were.

## Check on 2024

Fitted on the first three terms only (income {early['income'][0]:.2f}, unemployment
{early['unemployment'][0]:.2f}), the regional pattern of 2019 to 2024 (each region's swing
against Great Britain's) is predicted with a correlation of {res['check_correlation']:.2f}. {check_text}

## Observations

| Term ending | Region | Swing (log-odds) | Income growth, change (points) | Unemployment, change (points) |
|---|---|---:|---:|---:|
{rows}
"""


def write() -> dict:
    res = results()
    (OUT / "HISTORY.md").write_text(report(res), encoding="utf-8", newline="\n")
    return res


if __name__ == "__main__":
    extract()
    res = write()
    print(f"income {res['full']['income']}, unemployment {res['full']['unemployment']}, "
          f"combined {res['income']}, {res['unemployment']}, check correlation {res['check_correlation']:.2f}, "
          f"tenure {res['tenure']}")
