"""The 2024 general election and the census by constituency (stage S5.0).

    python tools/uk/elections.py       extract from the cached downloads and check

Reads, from .cache/uk/ (`python tools/uk/pipeline.py fetch ge2024 ge2024parties
census_age_pcon census_work_pcon`):

- the results of the UK general election of 4 July 2024 by candidate, from UK Parliament's
  election results site (Open Parliament Licence v3.0). Only votes by party and
  constituency are kept: candidates' names are personal data and are dropped;
- the same election's totals by party, to check against;
- Census 2021 usual residents by age (6 bands) and by economic activity, for the 575
  constituencies of England and Wales on the 2024 boundaries (ONS, Open Government
  Licence v3.0).

Writes into models/uk/data/elections/:

- ge2024.csv: per constituency, its code, name, region (a member of the model's region
  dimension), electorate, valid votes, votes by bloc, the votes of the best-placed candidate
  in the "other" bloc (first past the post counts candidates, and in two seats several
  independents together out-polled the winner), and the winning bloc;
- census_pcon.csv: per constituency of England and Wales, residents by age band and
  people aged 16 and over by economic activity;
- ELECTIONS.md: the sources, checksums, how parties map to blocs, and the checks: votes and
  seats by party equal the published totals, and the census tables cover the same
  constituencies and people.

The game shows blocs, not parties (docs/S5-PLAN.md): the parties are mapped to blocs here
and their names go no further.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "elections"

BLOCS = ["centre_left", "centre_right", "liberal", "populist_right", "green", "scottish_nationalist",
         "welsh_nationalist", "northern_ireland", "other"]
# Main party name -> bloc, outside Northern Ireland. Every candidate in Northern Ireland is
# in the northern_ireland bloc; any party not listed is "other".
PARTY_BLOC = {
    "Labour": "centre_left",
    "Conservative": "centre_right",
    "Liberal Democrat": "liberal",
    "Reform UK": "populist_right",
    "Green Party": "green",
    "Scottish Green Party": "green",
    "Scottish National Party": "scottish_nationalist",
    "Plaid Cymru": "welsh_nationalist",
}
REGIONS = {
    "North East": "north_east", "North West": "north_west", "Yorkshire and The Humber": "yorkshire",
    "East Midlands": "east_midlands", "West Midlands": "west_midlands", "East of England": "east",
    "London": "london", "South East": "south_east", "South West": "south_west",
    "Wales": "wales", "Scotland": "scotland", "Northern Ireland": "northern_ireland",
}
AGES = ["age_0_15", "age_16_24", "age_25_34", "age_35_49", "age_50_64", "age_65_plus"]
WORK = {"1": "in_employment", "2": "unemployed", "3": "inactive"}


def bloc_of(row: dict) -> str:
    if row["Country name"] == "Northern Ireland":
        return "northern_ireland"
    return PARTY_BLOC.get(row["Main party name"], "other")


def write(path: Path, header: list[str], rows: list[list]) -> None:
    buffer = io.StringIO()
    w = csv.writer(buffer, lineterminator="\n")
    w.writerow(header)
    w.writerows(rows)
    path.write_text(buffer.getvalue(), encoding="utf-8", newline="\n")


def census(name: str, column_of) -> dict[str, dict[str, int]]:
    data = json.loads((CACHE / f"{name}.json").read_text(encoding="utf-8"))
    out: dict[str, dict[str, int]] = {}
    for obs in data["observations"]:
        area, category = obs["dimensions"]
        out.setdefault(area["option_id"], {"name": area["option"]})
        column = column_of(category["option_id"])
        if column:
            out[area["option_id"]][column] = out[area["option_id"]].get(column, 0) + int(obs["observation"])
    return out


def main() -> int:
    text = (CACHE / "ge2024.csv").read_text(encoding="utf-8-sig")
    rows = list(csv.DictReader(io.StringIO(text)))
    problems: list[str] = []
    seats: dict[str, dict] = {}
    by_party_votes: dict[str, int] = {}
    by_party_won: dict[str, int] = {}
    for r in rows:
        code = r["Constituency geographic code"]
        region = REGIONS[r["English region name"] or r["Country name"]]
        seat = seats.setdefault(code, {"name": r["Constituency name"], "region": region,
                                       "electorate": int(r["Electorate"]), "valid": int(r["Election valid vote count"]),
                                       "votes": dict.fromkeys(BLOCS, 0), "winner": None, "other_best": 0})
        votes = int(r["Candidate vote count"])
        b = bloc_of(r)
        seat["votes"][b] += votes
        if b == "other":
            seat["other_best"] = max(seat["other_best"], votes)
        party = r["Main party name"] or "(independent)"
        by_party_votes[party] = by_party_votes.get(party, 0) + votes
        if r["Candidate result position"] == "1":
            seat["winner"] = b
            by_party_won[party] = by_party_won.get(party, 0) + 1
    # Checks against the totals by party and for the election.
    published = list(csv.DictReader(io.StringIO((CACHE / "ge2024parties.csv").read_text(encoding="utf-8-sig"))))
    for p in published:
        name = p["Party name"]
        if by_party_votes.get(name, 0) != int(p["Votes"]):
            problems.append(f"votes for {name}: {by_party_votes.get(name, 0)} against {p['Votes']} published")
        if by_party_won.get(name, 0) != int(p["Constituencies won"]):
            problems.append(f"seats for {name}: {by_party_won.get(name, 0)} against {p['Constituencies won']} published")
    total_valid = int(rows[0]["Total valid votes in general election"])
    total_electorate = int(rows[0]["Total electorate in general election"])
    if sum(s["valid"] for s in seats.values()) != total_valid:
        problems.append("valid votes by constituency do not add up to the election's total")
    if sum(sum(s["votes"].values()) for s in seats.values()) != total_valid:
        problems.append("votes by candidate do not add up to the election's valid votes")
    if sum(s["electorate"] for s in seats.values()) != total_electorate:
        problems.append("electorates do not add up to the election's total")
    if len(seats) != 650 or any(s["winner"] is None for s in seats.values()):
        problems.append(f"{len(seats)} constituencies, some without a winner")
    for code, s in seats.items():
        contest = dict(s["votes"], other=s["other_best"])
        if max(contest, key=contest.get) != s["winner"]:
            problems.append(f"{s['name']}: the largest bloc, counting the best other candidate, is not the winner")
        if sum(s["votes"].values()) != s["valid"]:
            problems.append(f"{s['name']}: votes by candidate {sum(s['votes'].values())} against {s['valid']} valid")

    age = census("census_age_pcon", lambda option: AGES[int(option) - 1])
    work = census("census_work_pcon", lambda option: WORK.get(option))
    ew = {c for c in seats if c[0] in "EW"}
    if set(age) != ew or set(work) != ew:
        problems.append(f"census constituencies {len(age)} and {len(work)} against {len(ew)} in England and Wales")
    for code in ew & set(age) & set(work):
        # ONS perturbs census cells slightly to protect confidentiality, so two tables of
        # the same people differ by a few; more than ten would be a different population.
        adults = sum(age[code][a] for a in AGES[1:])
        if abs(adults - sum(work[code].get(k, 0) for k in WORK.values())) > 10:
            problems.append(f"{age[code]['name']}: residents aged 16 and over differ between the census tables")

    OUT.mkdir(parents=True, exist_ok=True)
    order = sorted(seats, key=lambda c: (list(REGIONS.values()).index(seats[c]["region"]), c))
    write(OUT / "ge2024.csv", ["code", "name", "region", "electorate", "valid_votes", *BLOCS, "other_best", "winner"],
          [[c, seats[c]["name"], seats[c]["region"], seats[c]["electorate"], seats[c]["valid"],
            *(seats[c]["votes"][b] for b in BLOCS), seats[c]["other_best"], seats[c]["winner"]] for c in order])
    write(OUT / "census_pcon.csv", ["code", *AGES, *WORK.values()],
          [[c, *(age[c][a] for a in AGES), *(work[c].get(k, 0) for k in WORK.values())] for c in sorted(ew)])

    totals = {b: sum(s["votes"][b] for s in seats.values()) for b in BLOCS}
    won = {b: sum(1 for s in seats.values() if s["winner"] == b) for b in BLOCS}
    lines = ["# The 2024 general election and the census by constituency", "",
             "Generated by `python tools/uk/elections.py`; do not edit.", "",
             "Contains Parliamentary information licensed under the Open Parliament Licence v3.0 (results:",
             "UK Parliament, Election Results, general election of 4 July 2024). Source: Office for National",
             "Statistics licensed under the Open Government Licence v3.0 (Census 2021 by 2024 constituency).",
             "Candidates' names are not kept.", "", "| Cached file | Retrieved | SHA-256 |", "|---|---|---|"]
    for name in ("ge2024", "ge2024parties", "census_age_pcon", "census_work_pcon"):
        meta_path = CACHE / f"{name}.meta.json"
        meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        lines.append(f"| {name} | {meta.get('retrieved', 'unknown')} | `{meta.get('sha256', '')[:16]}...` |")
    lines += ["", "## Parties to blocs", "", "Every candidate in Northern Ireland is in the Northern Ireland bloc. Elsewhere:", "",
              "| Party | Bloc |", "|---|---|", *[f"| {p} | {b} |" for p, b in PARTY_BLOC.items()],
              "| any other party, independents, the Speaker | other |", "",
              "## The election by bloc", "", "| Bloc | Votes | Share | Seats |", "|---|---:|---:|---:|",
              *[f"| {b} | {totals[b]:,} | {totals[b] / total_valid * 100:.2f}% | {won[b]} |" for b in BLOCS],
              f"| all | {total_valid:,} | 100% | {sum(won.values())} |", "",
              f"Electorate {total_electorate:,}; turnout {total_valid / total_electorate * 100:.2f}% of the electorate (valid votes).", "",
              "## Checks", "",
              f"Votes and seats of every party against the published totals by party, the election's valid votes and "
              f"electorate, every constituency's votes against its valid vote count, and the census tables against "
              f"each other ({len(ew)} constituencies in England and Wales; ONS perturbs census cells to protect "
              f"confidentiality, so the tables may differ by up to ten people): "
              + ("all pass." if not problems else f"{len(problems)} failed:"), *problems, ""]
    (OUT / "ELECTIONS.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"ge2024.csv: {len(seats)} constituencies; census_pcon.csv: {len(ew)}; {len(problems)} check(s) failed")
    for b in BLOCS:
        print(f"  {b:22} {totals[b] / total_valid * 100:6.2f}%  {won[b]:3} seats")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
