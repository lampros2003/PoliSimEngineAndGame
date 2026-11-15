"""The UK's voters (stage S5.2): who votes for which bloc, from the synthetic households.

    python tools/uk/voters.py          (normally run by tools/uk/calibrate.py)

The adults of the households aged 18 and over are grouped into 600 voter types: region
(12) by age band (5) by household income quintile (5) by in work or not (2). For each type
and each option (nine blocs, or not voting) a utility:

    utility = intercept[region, option] + age effect[age band, option]
              + for the blocs in government: income effect * the type's change in real
                household income + the fundamentals (unemployment and inflation since the
                last election, time in office)

and the share of the type choosing each option is exp(utility) over the sum for the type
(a multinomial logit). The intercepts are fitted here so that in the base month every
region's shares of its electorate (each bloc, and not voting) are the 2024 general
election's. The age effects and the sizes of the fundamentals are assumptions, listed in
ASSUMPTIONS below and in models/uk/politics/README.md.

Writes, into the model folder: politics.toml (generated; do not edit) and politics/ with
the voter types and the fitted intercepts.
"""

from __future__ import annotations

import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGIONS = ["north_east", "north_west", "yorkshire", "east_midlands", "west_midlands", "east", "london", "south_east",
           "south_west", "wales", "scotland", "northern_ireland"]
BLOCS = ["centre_left", "centre_right", "liberal", "populist_right", "green", "scottish_nationalist",
         "welsh_nationalist", "northern_ireland", "other"]
BLOC_LABELS = ["Centre-left", "Centre-right", "Liberal", "Populist right", "Green", "Scottish nationalist",
               "Welsh nationalist", "Northern Ireland parties", "Others"]
OPTIONS = BLOCS + ["abstain"]
AGES = [("age_18_24", "18 to 24", 18, 24), ("age_25_34", "25 to 34", 25, 34), ("age_35_49", "35 to 49", 35, 49),
        ("age_50_64", "50 to 64", 50, 64), ("age_65_plus", "65 and over", 65, 90)]
ADULTS = 4

# Stage S13.4: the interest groups, in order: key, label, the name in a sentence, and who is
# in the group. A formula over the voter type's attributes is exact (1 or 0); the rest come
# from the households: the share of the type's adults aged 18 and over who are in the group.
GROUPS = [
    ("young", "The young", "the young", "type_age <= 1"),
    ("midlife", "Mid-life", "people in mid-life", "type_age == 2 or type_age == 3"),
    ("pensioners", "Pensioners", "pensioners", "type_age == 4"),
    ("low_income", "Low incomes", "low incomes", "type_quintile == 0"),
    ("middle_income", "Middle incomes", "middle incomes", "type_quintile >= 1 and type_quintile <= 3"),
    ("high_income", "High incomes", "high incomes", "type_quintile == 4"),
    ("in_work", "In work", "people in work", "type_in_work == 1"),
    ("out_of_work", "Out of work", "people out of work", "type_in_work == 0 and type_age <= 3"),
    ("parents", "Parents", "parents", None),
    ("lone_parents", "Lone parents", "lone parents", None),
    ("self_employed", "The self-employed", "the self-employed", None),
    ("scotland", "Scotland", "Scotland", "type_region == 10"),
    ("wales", "Wales", "Wales", "type_region == 9"),
    ("northern_ireland", "Northern Ireland", "Northern Ireland", "type_region == 11"),
    ("london", "London", "London", "type_region == 6"),
    ("north", "The North", "the North", "type_region <= 2"),
    ("midlands", "The Midlands", "the Midlands", "type_region == 3 or type_region == 4"),
    ("south", "The South", "the South", "type_region == 5 or type_region == 7 or type_region == 8"),
]
# The group dimension's member where the key is already an element's name (households.toml).
MEMBER = {"pensioners": "pensioner"}
# Each household group: the adult slots counted, and the condition on the household and slot.
HOUSEHOLD_GROUPS = {
    "parents": (range(1, ADULTS + 1), "children >= 1"),
    "lone_parents": (range(1, 2), "type == 7 and children >= 1"),  # adult 1 of a lone-parent family
    "self_employed": (range(1, ADULTS + 1), "self_employed{i}"),
}
# The same groups for one household: true when any of its adults is in the group ({i} is each
# adult in turn), or for the household as a whole. Every household has an adult; every adult is
# 18 or over; an absent adult has age -1, no earnings and is not self-employed.
HOUSEHOLD_FLAGS = {
    "young": "age{i} >= 18 and age{i} <= 34", "midlife": "age{i} >= 35 and age{i} <= 64", "pensioners": "age{i} >= 65",
    "low_income": "income_decile <= 2", "middle_income": "income_decile >= 3 and income_decile <= 8",
    "high_income": "income_decile >= 9",
    "in_work": "earnings{i} > 0", "out_of_work": "age{i} >= 18 and age{i} <= 64 and not (earnings{i} > 0)",
    "parents": "children >= 1", "lone_parents": "type == 7 and children >= 1", "self_employed": "self_employed{i}",
    "scotland": "region_code == 10", "wales": "region_code == 9", "northern_ireland": "region_code == 11",
    "london": "region_code == 6", "north": "region_code <= 2", "midlands": "region_code == 3 or region_code == 4",
    "south": "region_code == 5 or region_code == 7 or region_code == 8",
}
# The drivers of a group's approval: each a term of the governing blocs' utility, by voter type.
DRIVERS = [
    ("income", "income", "vote_income_effect * voter_income_change"),
    ("jobs", "jobs: unemployment in the region since the election", "voter_jobs"),
    ("prices_and_time", "prices and time in office", None),
    ("services", "services and the climate", "voter_services"),
    ("standing", "reactions to the government's decisions", "government_standing"),
]

ASSUMPTIONS = {
    # Age effects on utility (35 to 49 is the reference), by option. The 2024 election's
    # widely reported pattern: turnout rises with age; the young lean to the centre-left and
    # the greens, older voters to the centre-right and the populist right. Sized so that,
    # for example, the centre-right's odds among those 65 and over are some seven times
    # those among 18 to 24 year olds. The constituency results could not settle these: an
    # ecological regression on the census age mix gave impossible shares (docs/S5-PLAN.md).
    "age_effect": {
        "centre_left": [0.3, 0.3, 0.0, -0.1, -0.5],
        "centre_right": [-1.0, -0.7, 0.0, 0.3, 0.9],
        "liberal": [0.0, 0.0, 0.0, 0.0, 0.1],
        "populist_right": [-0.4, -0.3, 0.0, 0.3, 0.4],
        "green": [1.0, 0.6, 0.0, -0.4, -0.8],
        "scottish_nationalist": [0.2, 0.2, 0.0, 0.0, -0.3],
        "welsh_nationalist": [0.2, 0.2, 0.0, 0.0, -0.3],
        "northern_ireland": [0.0, 0.0, 0.0, 0.0, 0.0],
        "other": [0.0, 0.0, 0.0, 0.0, 0.0],
        "abstain": [0.9, 0.6, 0.0, -0.4, -0.8],
    },
    # The fundamentals, on the utility of the blocs in government. Sizes in the range of the
    # economic-voting literature: a 1% rise in a type's real household income adds about
    # half a point to the government's share among it; a point of unemployment since the
    # last election takes off about a point and a half; a point of inflation above the last
    # election's, under a point; each year in office about half a point.
    # Stage S6.0: { low, central, high } for the presets and screening; low is the weaker
    # effect. The literature's estimates of economic voting vary by about half either way.
    # Stage S9.4: the income and unemployment effects are then combined with their fit to the
    # elections of 2010 to 2024 (_with_history, below).
    "income_effect": {"low": 1.25, "central": 2.5, "high": 3.75},  # per unit of change in real household income
    "unemployment_effect": {"low": -3.0, "central": -6.0, "high": -9.0},  # per unit of unemployment rate
    "inflation_effect": {"low": -1.5, "central": -3.0, "high": -4.5},  # per unit of annual inflation
    "tenure_effect": {"low": -0.0125, "central": -0.025, "high": -0.05},  # per year in office
    "months_in_office": 6,  # the government took office in July 2024; the model starts in January 2025
    # Stage S8.3: the issues voters weigh beyond the economy, for the blocs in government:
    # each a change since the last election in a measure where 1 is how things stood (the
    # health, education and policing service levels, and the path to net zero over actual
    # emissions). Utility per unit of change, by age band (18-24, 25-34, 35-49, 50-64, 65+).
    # Judgements, sized so that a 10% fall in the health service costs the government about
    # as much among people over 65 as a point of unemployment (0.06); the young weigh the
    # environment most, people of an age to have children education, older people health
    # and policing. The voter types do not know their bloc, so age stands in for leaning.
    "issue_weight": {
        "health": [0.3, 0.3, 0.4, 0.5, 0.6],
        "education": [0.15, 0.3, 0.4, 0.2, 0.1],
        "policing": [0.15, 0.15, 0.2, 0.25, 0.3],
        "environment": [0.5, 0.4, 0.3, 0.2, 0.15],
    },
    "issue_scale": {"low": 0.5, "central": 1.0, "high": 1.5},
    "governing": ["centre_left"],
    # Stage S5.3. Positions on a left (-1) to right (+1) axis, for forming governments and
    # (S5.4) voting on bills: a judgement of where each bloc stands on tax and spending.
    "position": {"centre_left": -0.4, "centre_right": 0.4, "liberal": -0.1, "populist_right": 0.8, "green": -0.7,
                 "scottish_nationalist": -0.5, "welsh_nationalist": -0.5, "northern_ireland": 0.0, "other": 0.0},
    "parliament_months": 60,  # a Parliament's longest life; the 2024 one ends in July 2029
    "months_since_election": 6,
}


def _with_history() -> None:
    """Stage S9.4: the income and unemployment effects above are the judgements; each is
    combined with its fit to the general elections of 2010 to 2024 (tools/uk/history.py,
    models/uk/data/elections/HISTORY.md), weighted by precision, and the result is used."""
    import sys
    here = str(Path(__file__).resolve().parent)
    if here not in sys.path:
        sys.path.insert(0, here)
    import history
    fitted = history.results()
    for key, name in (("income_effect", "income"), ("unemployment_effect", "unemployment")):
        if ASSUMPTIONS[key] != history.PRIOR[name]:
            raise SystemExit(f"voters: the judgement for {key} differs from history.PRIOR")
        ASSUMPTIONS[key] = {k: fitted[name][k] for k in ("low", "central", "high")}


_with_history()


def voter_types() -> list[tuple[int, int, int, int]]:
    """(region, age band, income quintile, in work) for each voter type, in order."""
    return [(r, a, q, w) for r in range(len(REGIONS)) for a in range(len(AGES)) for q in range(5) for w in range(2)]


def age_band(age: int) -> int:
    return next((k for k, (_, _, lo, hi) in enumerate(AGES) if lo <= age <= hi), 0)


def base_voters(households: Path) -> list[float]:
    """Adults aged 18 and over by voter type, from the households and their weights."""
    voters = [0.0] * len(voter_types())
    with open(households, newline="", encoding="utf-8") as handle:
        for r in csv.DictReader(handle):
            w = int(r["weight"])
            quintile = (int(r["income_decile"]) - 1) // 2
            for i in range(1, ADULTS + 1):
                age = int(r[f"age{i}"])
                if int(r["adults"]) >= i and age >= 18:
                    work = 1 if float(r[f"earnings{i}"]) > 0 else 0
                    voters[((int(r["region_code"]) * 5 + age_band(age)) * 5 + quintile) * 2 + work] += w
    return voters


def election_targets() -> list[list[float]]:
    """Each region's 2024 shares of its electorate: each bloc, then not voting."""
    votes = [[0] * len(BLOCS) for _ in REGIONS]
    electorate, valid = [0] * len(REGIONS), [0] * len(REGIONS)
    with open(ROOT / "models" / "uk" / "data" / "elections" / "ge2024.csv", newline="", encoding="utf-8") as handle:
        for s in csv.DictReader(handle):
            r = REGIONS.index(s["region"])
            electorate[r] += int(s["electorate"])
            valid[r] += int(s["valid_votes"])
            for b, bloc in enumerate(BLOCS):
                votes[r][b] += int(s[bloc])
    return [[v / electorate[r] for v in votes[r]] + [1 - valid[r] / electorate[r]] for r in range(len(REGIONS))]


def fit(voters: list[float], targets: list[list[float]], preset: str = "central") -> tuple[list[list[float]], float]:
    """Regional intercepts by iterative scaling, so that each region's predicted shares of
    its adults equal its targets under a preset's time-in-office effect. Options with no
    votes in a region get -30 (a share of about 1e-13). Returns the intercepts and the
    largest error left."""
    a = ASSUMPTIONS
    gov = [1.0 if b in a["governing"] else 0.0 for b in OPTIONS]
    base = a["tenure_effect"][preset] * a["months_in_office"] / 12  # the fundamentals in the base month
    types = voter_types()
    alpha = [[(math.log(t) if t > 0 else -30.0) for t in targets[r]] for r in range(len(REGIONS))]
    worst = 1.0
    for _ in range(500):
        predicted = [[0.0] * len(OPTIONS) for _ in REGIONS]
        total = [0.0] * len(REGIONS)
        for (r, ag, _, _), n in zip(types, voters):
            u = [alpha[r][o] + a["age_effect"][opt][ag] + gov[o] * base for o, opt in enumerate(OPTIONS)]
            e = [math.exp(x) for x in u]
            s = sum(e)
            for o in range(len(OPTIONS)):
                predicted[r][o] += n * e[o] / s
            total[r] += n
        worst = 0.0
        for r in range(len(REGIONS)):
            for o in range(len(OPTIONS)):
                if targets[r][o] > 0:
                    share = predicted[r][o] / total[r]
                    worst = max(worst, abs(share - targets[r][o]))
                    alpha[r][o] += math.log(targets[r][o] / share)
            shift = alpha[r][-1]  # not voting is the reference
            alpha[r] = [x - shift if x > -29 else -30.0 for x in alpha[r]]
        if worst < 1e-12:
            break
    return alpha, worst


def write(out_dir: Path, households: Path) -> tuple[str, float]:
    """Writes out_dir/politics/ and returns the text of politics.toml and the fit."""
    folder = out_dir / "politics"
    folder.mkdir(parents=True, exist_ok=True)
    voters = base_voters(households)
    fitted = {p: fit(voters, election_targets(), p) for p in ("low", "central", "high")}
    worst = max(w for _, w in fitted.values())

    def table(name: str, header: str, lines: list[str]) -> None:
        (folder / name).write_text(header + "\n" + "\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    table("voter_types.csv", "voter_type,region,voter_age,quintile,in_work",
          [f"{t},{r},{a},{q},{w}" for t, (r, a, q, w) in enumerate(voter_types())])
    table("intercepts.csv", "region,option,low,central,high",
          [f"{REGIONS[r]},{o}," + ",".join(repr(fitted[p][0][r][k]) for p in ("low", "central", "high"))
           for r in range(len(REGIONS)) for k, o in enumerate(OPTIONS)])
    table("age_effects.csv", "voter_age,option,value",
          [f"{AGES[g][0]},{o},{ASSUMPTIONS['age_effect'][o][g]!r}" for g in range(len(AGES)) for o in OPTIONS])
    table("voter_ages.csv", "age,value", [f"{age},{age_band(age)}" for age in range(91)])
    table("quintiles.csv", "decile,value", [f"{d},{(d - 1) // 2}" for d in range(1, 11)])
    table("governing.csv", "bloc,value", [f"{b},{str(b in ASSUMPTIONS['governing']).lower()}" for b in BLOCS])
    table("positions.csv", "bloc,value", [f"{b},{ASSUMPTIONS['position'][b]!r}" for b in BLOCS])
    table("issue_weights.csv", "voter_age,issue,value",
          [f"{AGES[g][0]},{i},{w[g]!r}" for g in range(len(AGES)) for i, w in ASSUMPTIONS["issue_weight"].items()])
    with open(ROOT / "models" / "uk" / "data" / "labour_regions.csv", newline="", encoding="utf-8") as handle:
        labour = {r["region"]: (int(r["employed"]), int(r["unemployed"])) for r in csv.DictReader(handle)}
    national = sum(u for _, u in labour.values()) / sum(e + u for e, u in labour.values())
    table("regional_unemployment.csv", "region,value",
          [f"{r},{labour[r][1] / sum(labour[r]) / national!r}" for r in REGIONS])
    seats = constituencies()
    table("constituencies.csv", "constituency,region,winner",
          [f"{c['code']},{REGIONS.index(c['region'])},{BLOCS.index(c['winner'])}" for c in seats])
    table("seat_shares.csv", "constituency,bloc,value",
          [f"{c['code']},{b},{c['shares'][k]!r}" for c in seats for k, b in enumerate(BLOCS)])
    regional = election_targets()
    table("regional_shares.csv", "region,bloc,value",
          [f"{REGIONS[r]},{b},{regional[r][k] / (1 - regional[r][-1])!r}" for r in range(len(REGIONS))
           for k, b in enumerate(BLOCS)])
    won = [sum(1 for c in seats if c["winner"] == b) for b in BLOCS]
    table("seats.csv", "bloc,value", [f"{b},{n}" for b, n in zip(BLOCS, won)])
    return rules(seats), worst


def constituencies() -> list[dict]:
    """The 650 seats in 2024: code, name, region, each bloc's share of the valid votes (the
    "other" bloc by its best-placed candidate, as first past the post counts) and winner."""
    out = []
    with open(ROOT / "models" / "uk" / "data" / "elections" / "ge2024.csv", newline="", encoding="utf-8") as handle:
        for s in csv.DictReader(handle):
            valid = int(s["valid_votes"])
            votes = [int(s[b]) for b in BLOCS[:-1]] + [int(s["other_best"])]
            out.append({"code": s["code"], "name": s["name"], "region": s["region"], "winner": s["winner"],
                        "shares": [v / valid for v in votes]})
    return out


def groups() -> str:
    """Stage S13.4: the interest groups, their share of the electorate, their approval of the
    government and its drivers, and the same groups and support for each household."""
    out = f'''
# ---- stage S13.4: interest groups (models/uk/politics/README.md, Groups)

[dim.group]
members = [{", ".join(f'"{MEMBER.get(g[0], g[0])}"' for g in GROUPS)}]
labels = [{", ".join(f'"{g[1]}"' for g in GROUPS)}]
'''
    for key, (slots, cond) in HOUSEHOLD_GROUPS.items():
        terms = " + ".join(f"wsum_by(household, select({cond.format(i=i)}, adult_voter{i}, 0), voter_type, voter_type_of{i})"
                           for i in slots)
        out += f'''
[var.voters_{key}]
doc = "Adults aged 18 and over in the group '{key}', by voter type, from the households"
type = "int"
unit = "person"
phase = "politics"
dims = ["voter_type"]
expr = "{terms}"
'''
    member = "0.0"
    for k in reversed(range(len(GROUPS))):
        key, _, _, cond = GROUPS[k]
        here = f"safe_div(1.0 * voters_{key}, 1.0 * voters, 0.0)" if cond is None else f"select({cond}, 1.0, 0.0)"
        member = here if k == len(GROUPS) - 1 else f"select(coord(group) == {k}, {here}, {member})"
    out += f'''
[var.group_member]
doc = "The share of each voter type's adults in each group: 1 or 0 by the type's region, age band, income quintile and work; from the households for parents, lone parents and the self-employed"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type", "group"]
expr = "{member}"

[var.governing_choice]
doc = "Share of each voter type choosing a governing bloc"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "sum(select(governing, choice[option: coord(bloc)], 0.0), bloc)"

[var.group_voters]
type = "real"
unit = "person"
phase = "politics"
dims = ["group"]
expr = "sum(voters * group_member, voter_type)"

[var.group_share]
label = "Share of the electorate, by group"
type = "real"
unit = "1"
phase = "politics"
dims = ["group"]
expr = "group_voters / sum(voters, voter_type)"

[var.group_approval]
label = "Approval of the government, by group"
doc = "The share of the group's likely voters (those who would vote) who would vote for a governing bloc"
type = "real"
unit = "1"
phase = "politics"
dims = ["group"]
expr = "sum(voters * group_member * governing_choice, voter_type) / sum(voters * group_member * (1.0 - choice[option: abstain]), voter_type)"
'''
    tenure = f"vote_tenure_effect * {ASSUMPTIONS['months_in_office']} / 12.0"
    for key, words, term in DRIVERS:
        if term is None:
            expr = f"fundamentals - {tenure}"
            doc = ("Inflation since the last election and time in office, the same for every group; less the base "
                   "month's time in office, which the intercepts were fitted with")
        else:
            expr = f"sum(voters * group_member * {term}, voter_type) / group_voters"
            doc = "The group's mean, weighted by adults, of this term of the governing blocs' utility"
        out += f'''
[var.group_driver_{key}]
label = "Approval drivers: {words}"
doc = "{doc}"
type = "real"
unit = "1"
phase = "politics"
dims = ["group"]
expr = "{expr}"
'''
    for k, (key, _, words, _) in enumerate(GROUPS):
        out += f'''
[var.approval_{key}]
label = "Approval: {words}"
type = "real"
unit = "1"
phase = "politics"
expr = "group_approval[group: {k}]"

[var.share_{key}]
label = "Share of the electorate: {words}"
type = "real"
unit = "1"
phase = "politics"
expr = "group_share[group: {k}]"
'''
    # Each household: which groups its adults are in, and their support (every adult is 18 or over).
    voter = "age{i} >= 18"
    out += f'''
[var.household_support]
label = "Support for the government in the household"
doc = "The mean, over the household's adults aged 18 and over, of their voter type's share choosing a governing bloc"
type = "real"
unit = "1"
phase = "politics"
entity = "household"
expr = "safe_div({" + ".join(f"select({voter.format(i=i)}, governing_choice[voter_type: voter_type_of{i}], 0.0)" for i in range(1, ADULTS + 1))}, 1.0 * adults, 0.0)"
'''
    for key, label, _, _ in GROUPS:
        flag = HOUSEHOLD_FLAGS[key]
        expr = " or ".join(f"({flag.format(i=i)})" for i in range(1, ADULTS + 1)) if "{i}" in flag else flag
        out += f'''
[var.household_in_{key}]
label = "In the group: {label}"
type = "bool"
unit = "1"
phase = "politics"
entity = "household"
expr = "{expr}"
'''
    return out


def rules(seats: list[dict]) -> str:
    a = ASSUMPTIONS
    groups_section = groups()

    def slots(term: str) -> str:
        return " + ".join(f"wsum_by(household, {term.format(i=i)}, voter_type, voter_type_of{i})"
                          for i in range(1, ADULTS + 1))
    adult = "adult_voter{i}"
    # Stage S10.3: each adult's voter type and count, once per household, for the sums
    # over voter types to read.
    slot_vars = "\n".join(f"""[var.voter_type_of{i}]
doc = "The voter type of the household's adult {i}: region, age band, income quintile and work"
type = "int"
unit = "1"
phase = "politics"
entity = "household"
expr = "((region_code * 5 + voter_age_of[age: max(age{i}, 0)]) * 5 + quintile_of[decile: income_decile]) * 2 + select(earnings{i} > 0, 1, 0)"

[var.adult_voter{i}]
doc = "1 if the household's adult {i} is there and 18 or over, a person, else 0"
type = "int"
unit = "person/household"
phase = "politics"
entity = "household"
expr = "select(adults >= {i} and age{i} >= 18, person_each, 0)"
""" for i in range(1, ADULTS + 1))
    options = ", ".join(f'"{o}"' for o in OPTIONS)
    option_labels = ", ".join(f'"{x}"' for x in BLOC_LABELS + ["Would not vote"])
    blocs = ", ".join(f'"{b}"' for b in BLOCS)
    bloc_labels = ", ".join(f'"{x}"' for x in BLOC_LABELS)
    ages = ", ".join(f'"{g[0]}"' for g in AGES)
    issues = ", ".join(f'"{i}"' for i in ASSUMPTIONS["issue_weight"])
    scale_low, scale_central, scale_high = (ASSUMPTIONS["issue_scale"][k] for k in ("low", "central", "high"))
    codes = ", ".join(f'"{c["code"]}"' for c in seats)
    names = ", ".join('"' + c["name"].replace('"', "'") + '"' for c in seats)
    age_labels = ", ".join(f'"{g[1]}"' for g in AGES)
    return f'''# The UK's voters (stage S5.2). GENERATED by tools/uk/voters.py; do not edit.
# Who votes for which bloc: the households' adults aged 18 and over in 600 voter types,
# with a multinomial logit over nine blocs and not voting (models/uk/politics/README.md).

# Stage S5.4: changes to levers with a leaning are bills, voted on by these seats.
[legislature]
seats = "seats"
governing = "governing"
position = "bloc_position"
# Stage S12.4: bills cost political capital (capital.toml).
capital = "political_capital"
spent = "capital_spent"
bill_cost = "capital_bill"
swing_cost = "capital_swing"

[dim.option]
members = [{options}]
labels = [{option_labels}]

[dim.bloc]
doc = "The blocs: the first nine options"
members = [{blocs}]
labels = [{bloc_labels}]

[dim.voter_age]
members = [{ages}]
labels = [{age_labels}]

[dim.voter_type]
doc = "Region by age band by household income quintile by in work: see politics/voter_types.csv"
range = [0, 599]

[param.voter_age_of]
type = "int"
unit = "1"
dims = ["age"]
data = "politics/voter_ages.csv"

[param.quintile_of]
type = "int"
unit = "1"
dims = ["decile"]
data = "politics/quintiles.csv"

[param.type_region]
type = "int"
unit = "1"
dims = ["voter_type"]
data = "politics/voter_types.csv"
column = "region"

[param.type_age]
type = "int"
unit = "1"
dims = ["voter_type"]
data = "politics/voter_types.csv"
column = "voter_age"

[param.type_quintile]
doc = "Each voter type's household income quintile, 0 for the poorest fifth"
type = "int"
unit = "1"
dims = ["voter_type"]
data = "politics/voter_types.csv"
column = "quintile"

[param.type_in_work]
doc = "1 for voter types in work, 0 for the rest"
type = "int"
unit = "1"
dims = ["voter_type"]
data = "politics/voter_types.csv"
column = "in_work"

[param.option_intercept]
doc = "Fitted, preset by preset, so that the base month reproduces the 2024 general election in every region"
type = "real"
unit = "1"
dims = ["region", "option"]
data = "politics/intercepts.csv"
columns = {{ low = "low", central = "central", high = "high" }}

[param.option_age_effect]
doc = "Assumed: turnout rises with age; the young lean centre-left and green, the old centre-right and populist right"
type = "real"
unit = "1"
dims = ["voter_age", "option"]
data = "politics/age_effects.csv"

[param.vote_income_effect]
doc = "On the governing blocs' utility, per unit of proportional change in a voter type's real household income"
type = "real"
unit = "1"
low = {a["income_effect"]["low"]!r}
central = {a["income_effect"]["central"]!r}
high = {a["income_effect"]["high"]!r}

[param.vote_unemployment_effect]
doc = "On the governing blocs' utility, per unit of unemployment rate above its level at the last election"
type = "real"
unit = "1"
low = {a["unemployment_effect"]["low"]!r}
central = {a["unemployment_effect"]["central"]!r}
high = {a["unemployment_effect"]["high"]!r}

[param.vote_inflation_effect]
doc = "On the governing blocs' utility, per unit of annual inflation above its level at the last election"
type = "real"
unit = "1"
low = {a["inflation_effect"]["low"]!r}
central = {a["inflation_effect"]["central"]!r}
high = {a["inflation_effect"]["high"]!r}

[param.vote_tenure_effect]
doc = "On the governing blocs' utility, per year in office"
type = "real"
unit = "1"
low = {a["tenure_effect"]["low"]!r}
central = {a["tenure_effect"]["central"]!r}
high = {a["tenure_effect"]["high"]!r}

[state.governing]
label = "In government"
type = "bool"
unit = "1"
phase = "politics"
dims = ["bloc"]
initial = {{ data = "politics/governing.csv" }}
next = "select(election_now, would_govern, governing)"

[state.months_in_office]
label = "Months the government has held office"
type = "int"
unit = "1"
phase = "politics"
initial = {a["months_in_office"]}
next = "select(election_now and government_changes, 1, months_in_office + 1)"

[state.inflation_at_election]
doc = "Inflation at the last election; the base month's stands in for July 2024's (-1 until it is known)"
type = "real"
unit = "1"
phase = "politics"
initial = -1.0
next = "select(inflation_at_election < -0.5 or election_now, consumer_inflation_annual, inflation_at_election)"

# ---- each household's change in real income, the pocketbook

[var.real_net_income]
type = "real"
unit = "GBP/month/household"
phase = "politics"
entity = "household"
expr = "net_income / consumer_price_index"

[state.income_memory]
doc = "Real net income, averaged over about a year (exponentially); 0 until the first month"
type = "real"
unit = "GBP/month/household"
phase = "politics"
entity = "household"
initial = 0.0
next = "select(income_memory > 0.0, income_memory + (real_net_income - income_memory) / 12.0, real_net_income)"

[var.income_change]
label = "Change in real net income on about a year before"
doc = "Real net income against its average over about a year"
type = "real"
unit = "1"
phase = "politics"
entity = "household"
expr = "select(income_memory > 0.0 and real_net_income > 0.0, real_net_income / income_memory - 1.0, 0.0)"

# ---- voter types

{slot_vars}
[var.voters]
label = "Adults aged 18 and over, by voter type"
type = "int"
unit = "person"
phase = "politics"
dims = ["voter_type"]
expr = "{slots(adult)}"

[var.voter_income_change]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "safe_div({slots("income_change * " + adult)}, voters, 0.0)"

[var.fundamentals]
label = "Inflation and time in office, on the government's utility"
type = "real"
unit = "1"
phase = "politics"
expr = "select(inflation_at_election < -0.5, 0.0, vote_inflation_effect * (consumer_inflation_annual - inflation_at_election)) + vote_tenure_effect * months_in_office / 12.0"

# ---- unemployment by region (stage S6.2): the national rate times the region's relative
# rate in the Annual Population Survey of 2024; voters weigh their own region's.

[param.regional_unemployment_ratio]
doc = "Each region's unemployment rate against the UK's, Annual Population Survey, 2024"
type = "real"
unit = "1"
dims = ["region"]
data = "politics/regional_unemployment.csv"

[var.regional_unemployment]
label = "Unemployment rate by region"
type = "real"
unit = "1"
phase = "politics"
dims = ["region"]
expr = "unemployment_rate * regional_unemployment_ratio"

[state.regional_unemployment_at_election]
doc = "Unemployment by region at the last election; the base month's stands in for July 2024's (-1 until it is known)"
type = "real"
unit = "1"
phase = "politics"
dims = ["region"]
initial = -1.0
next = "select(regional_unemployment_at_election < 0.0 or election_now, regional_unemployment, regional_unemployment_at_election)"

# ---- stage S8.3: the issues voters weigh beyond the economy

[dim.issue]
members = [{issues}]
labels = ["Health", "Education", "Policing", "The environment"]

# Stage S11.3: how voters take a change in an issue since the last election, a judgement
# (docs/S11-PLAN.md). A fall counts half as much again as a rise; a rise counts in full up
# to a fifth, and half beyond; level beyond a doubling or a halving. Voters punish what got
# worse more than they reward what got better.
[table.issue_reaction]
kind = "curve"
x_unit = "1"
unit = "1"
points = [{{ x = -1.0, y = -1.5 }}, {{ x = 0.0, y = 0.0 }}, {{ x = 0.2, y = 0.2 }}, {{ x = 1.0, y = 0.6 }}]

[param.issue_weight]
doc = "How much each age band weighs each issue: utility for the government per unit of change since the last election (a judgement)"
type = "real"
unit = "1"
dims = ["voter_age", "issue"]
data = "politics/issue_weights.csv"

[param.issue_weight_scale]
doc = "How much the issues count at all, against the central judgement"
type = "real"
unit = "1"
low = {scale_low!r}
central = {scale_central!r}
high = {scale_high!r}

[var.issue_measure]
label = "The issues, by measure"
doc = "Where each issue stands, 1 as at the start: the health, education and policing service levels, and the path to net zero over actual emissions"
type = "real"
unit = "1"
phase = "politics"
dims = ["issue"]
expr = "select(coord(issue) == 0, service_level[function: 0], select(coord(issue) == 1, service_level[function: 1], select(coord(issue) == 2, service_level[function: 3], net_zero_path / emissions)))"

[state.issue_at_election]
doc = "Each issue's measure at the last election; the base month's stands in for July 2024's (-1 until it is known)"
type = "real"
unit = "1"
phase = "politics"
dims = ["issue"]
initial = -1.0
next = "select(issue_at_election < 0.0 or election_now, issue_measure, issue_at_election)"

[var.government_standing]
label = "Answers to dilemmas, on the government's standing"
doc = "What the government's answers to the questions put to it add to or take from its standing with each kind of voter (stage S9.2); nothing until an answer that changes it is in force"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "0.0 * type_age"

[var.voter_jobs]
doc = "Unemployment in the voter type's region against its level at the last election, on the government's utility (stage S13.4: a driver of approval)"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "select(regional_unemployment_at_election[region: type_region] < 0.0, 0.0, vote_unemployment_effect * (regional_unemployment[region: type_region] - regional_unemployment_at_election[region: type_region]))"

[var.voter_services]
doc = "The issues the voter type weighs, services and the climate, against the last election, on the government's utility (stage S13.4: a driver of approval)"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "issue_weight_scale * sum(select(issue_at_election < 0.0, 0.0, issue_weight[voter_age: type_age] * curve(issue_measure - issue_at_election, issue_reaction)), issue)"

[var.voter_fundamentals]
doc = "The fundamentals for each voter type: inflation, time in office, its own region's unemployment, the issues it weighs, and answers to dilemmas"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "government_standing + fundamentals + voter_jobs + voter_services"

[var.utility]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type", "option"]
expr = "option_intercept[region: type_region] + option_age_effect[voter_age: type_age] + select(coord(option) < 9 and governing[bloc: min(coord(option), 8)], vote_income_effect * voter_income_change + voter_fundamentals, 0.0)"

[var.weight_of_option]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type", "option"]
expr = "exp(utility)"

[var.weight_of_type]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "sum(weight_of_option, option)"

[var.choice]
label = "Share of each voter type choosing each option"
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type", "option"]
expr = "weight_of_option / weight_of_type"

[var.electorate_share]
label = "Share of the electorate, by option"
type = "real"
unit = "1"
phase = "politics"
dims = ["option"]
expr = "sum(voters * choice, voter_type) / sum(voters, voter_type)"

[var.turnout]
label = "Turnout"
type = "real"
unit = "1"
phase = "politics"
expr = "1.0 - electorate_share[option: abstain]"

[var.vote_intention]
label = "Voting intention"
type = "real"
unit = "1"
phase = "politics"
dims = ["bloc"]
expr = "electorate_share[option: coord(bloc)] / turnout"

[var.regional_intention]
label = "Voting intention by region"
type = "real"
unit = "1"
phase = "politics"
dims = ["region", "bloc"]
expr = "sum_by(voters * choice[option: coord(bloc)], voter_type, type_region, region) / sum_by(voters * (1.0 - choice[option: abstain]), voter_type, type_region, region)"

[var.government_support]
label = "Government's poll rating"
type = "real"
unit = "1"
phase = "politics"
expr = "sum(select(governing, vote_intention, 0.0), bloc)"
{groups_section}
# ------------------------------------------------------------------ seats (stage S5.3)
# Each seat's 2024 shares, scaled by its region's swing (proportional), first past the post.

[dim.constituency]
members = [{codes}]
labels = [{names}]

[dim.rival]
doc = "The blocs again, to compare each bloc with every other"
members = [{blocs}]

[param.seat_region]
type = "int"
unit = "1"
dims = ["constituency"]
data = "politics/constituencies.csv"
column = "region"

[param.seat_share_2024]
doc = "Each bloc's share of the valid votes in 2024 (the other bloc's by its best candidate)"
type = "real"
unit = "1"
dims = ["constituency", "bloc"]
data = "politics/seat_shares.csv"

[param.regional_share_2024]
type = "real"
unit = "1"
dims = ["region", "bloc"]
data = "politics/regional_shares.csv"

[param.bloc_position]
doc = "Left (-1) to right (+1) on tax and spending: a judgement"
type = "real"
unit = "1"
dims = ["bloc"]
data = "politics/positions.csv"

[param.parliament_months]
doc = "Months from one general election to the next"
type = "int"
unit = "1"
value = {a["parliament_months"]}

[param.majority]
doc = "Seats needed to govern alone: more than half of 650"
type = "int"
unit = "seat"
value = 326

[param.seat_each]
doc = "One seat per constituency won"
type = "int"
unit = "seat"
value = 1

[state.months_since_election]
label = "Months since the last general election"
type = "int"
unit = "1"
phase = "politics"
initial = {a["months_since_election"]}
next = "select(election_now, 1, months_since_election + 1)"

[var.months_to_election]
label = "Months to the next general election"
type = "int"
unit = "1"
phase = "politics"
expr = "parliament_months - months_since_election"

[var.election_now]
label = "A general election this month"
type = "bool"
unit = "1"
phase = "politics"
expr = "months_since_election >= parliament_months"

[var.projected_share]
label = "Share of the vote by seat, if an election were held now"
type = "real"
unit = "1"
phase = "politics"
dims = ["constituency", "bloc"]
expr = "seat_share_2024 * safe_div(regional_intention[region: seat_region], regional_share_2024[region: seat_region], 0.0)"

[var.seat_won]
type = "bool"
unit = "1"
phase = "politics"
dims = ["constituency", "bloc"]
expr = "sum(select(projected_share[bloc: coord(rival)] > projected_share or projected_share[bloc: coord(rival)] == projected_share and coord(rival) < coord(bloc), 1, 0), rival) == 0"

[var.projected_seats]
label = "Seats, if an election were held now"
type = "int"
unit = "seat"
phase = "politics"
dims = ["bloc"]
expr = "sum(select(seat_won, seat_each, 0), constituency)"

[state.seats]
label = "Seats in the House of Commons"
type = "int"
unit = "seat"
phase = "politics"
dims = ["bloc"]
initial = {{ data = "politics/seats.csv" }}
next = "select(election_now, projected_seats, seats)"

[state.seat_holder]
label = "The bloc holding each seat"
type = "int"
unit = "1"
phase = "politics"
dims = ["constituency"]
initial = {{ data = "politics/constituencies.csv", column = "winner" }}
next = "select(election_now, sum(select(seat_won, coord(bloc), 0), bloc), seat_holder)"

# ---- forming a government: the largest bloc, then the nearest blocs until a majority

[var.largest_bloc]
type = "bool"
unit = "1"
phase = "politics"
dims = ["bloc"]
expr = "sum(select(projected_seats[bloc: coord(rival)] > projected_seats or projected_seats[bloc: coord(rival)] == projected_seats and coord(rival) < coord(bloc), 1, 0), rival) == 0"

[var.leader_position]
type = "real"
unit = "1"
phase = "politics"
expr = "sum(select(largest_bloc, bloc_position, 0.0), bloc)"

[var.distance_from_leader]
type = "real"
unit = "1"
phase = "politics"
dims = ["bloc"]
expr = "abs(bloc_position - leader_position)"

[var.would_govern]
doc = "In the government an election now would form: the largest bloc, then the nearest, until a majority"
type = "bool"
unit = "1"
phase = "politics"
dims = ["bloc"]
expr = "projected_seats > 0 and sum(select(distance_from_leader[bloc: coord(rival)] < distance_from_leader or distance_from_leader[bloc: coord(rival)] == distance_from_leader and coord(rival) < coord(bloc), projected_seats[bloc: coord(rival)], 0), rival) < majority"

[var.government_changes]
doc = "This month's election changes which blocs govern"
type = "bool"
unit = "1"
phase = "politics"
expr = "election_now and sum(select(would_govern != governing, 1, 0), bloc) > 0"

[var.government_seats]
label = "Seats of the governing blocs"
doc = "After this month's election, if there is one"
type = "int"
unit = "seat"
phase = "politics"
expr = "sum(select(select(election_now, would_govern, governing), select(election_now, projected_seats, seats), 0), bloc)"

[var.player_governs]
label = "The player's bloc is in government"
type = "bool"
unit = "1"
phase = "politics"
expr = "select(election_now, would_govern[bloc: centre_left], governing[bloc: centre_left])"
'''


if __name__ == "__main__":
    import sys
    text, worst = write(ROOT / "models" / "uk", ROOT / "models" / "uk" / "households" / "households.csv")
    (ROOT / "models" / "uk" / "politics.toml").write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote models/uk/politics.toml and politics/; base month fit: largest error {worst:.2e}")
    sys.exit(0)
