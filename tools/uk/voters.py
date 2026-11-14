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
    "income_effect": 2.5,  # per unit of proportional change in real household income
    "unemployment_effect": -6.0,  # per unit of unemployment rate
    "inflation_effect": -3.0,  # per unit of annual inflation
    "tenure_effect": -0.025,  # per year in office
    "months_in_office": 6,  # the government took office in July 2024; the model starts in January 2025
    "governing": ["centre_left"],
    # Stage S5.3. Positions on a left (-1) to right (+1) axis, for forming governments and
    # (S5.4) voting on bills: a judgement of where each bloc stands on tax and spending.
    "position": {"centre_left": -0.4, "centre_right": 0.4, "liberal": -0.1, "populist_right": 0.8, "green": -0.7,
                 "scottish_nationalist": -0.3, "welsh_nationalist": -0.35, "northern_ireland": 0.0, "other": 0.0},
    "parliament_months": 60,  # a Parliament's longest life; the 2024 one ends in July 2029
    "months_since_election": 6,
}


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


def fit(voters: list[float], targets: list[list[float]]) -> tuple[list[list[float]], float]:
    """Regional intercepts by iterative scaling, so that each region's predicted shares of
    its adults equal its targets. Options with no votes in a region get -30 (a share of
    about 1e-13). Returns the intercepts and the largest error left."""
    a = ASSUMPTIONS
    gov = [1.0 if b in a["governing"] else 0.0 for b in OPTIONS]
    base = a["tenure_effect"] * a["months_in_office"] / 12  # the fundamentals in the base month
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
    alpha, worst = fit(voters, election_targets())

    def table(name: str, header: str, lines: list[str]) -> None:
        (folder / name).write_text(header + "\n" + "\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    table("voter_types.csv", "voter_type,region,voter_age,quintile,in_work",
          [f"{t},{r},{a},{q},{w}" for t, (r, a, q, w) in enumerate(voter_types())])
    table("intercepts.csv", "region,option,value",
          [f"{REGIONS[r]},{o},{alpha[r][k]!r}" for r in range(len(REGIONS)) for k, o in enumerate(OPTIONS)])
    table("age_effects.csv", "voter_age,option,value",
          [f"{AGES[g][0]},{o},{ASSUMPTIONS['age_effect'][o][g]!r}" for g in range(len(AGES)) for o in OPTIONS])
    table("voter_ages.csv", "age,value", [f"{age},{age_band(age)}" for age in range(91)])
    table("quintiles.csv", "decile,value", [f"{d},{(d - 1) // 2}" for d in range(1, 11)])
    table("governing.csv", "bloc,value", [f"{b},{str(b in ASSUMPTIONS['governing']).lower()}" for b in BLOCS])
    table("positions.csv", "bloc,value", [f"{b},{ASSUMPTIONS['position'][b]!r}" for b in BLOCS])
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


def rules(seats: list[dict]) -> str:
    a = ASSUMPTIONS

    def slots(term: str) -> str:
        parts = []
        for i in range(1, ADULTS + 1):
            key = (f"((region_code * 5 + voter_age_of[age: max(age{i}, 0)]) * 5 + quintile_of[decile: income_decile]) * 2"
                   f" + select(earnings{i} > 0, 1, 0)")
            parts.append(f"wsum_by(household, {term.format(i=i)}, voter_type, {key})")
        return " + ".join(parts)
    adult = "select(adults >= {i} and age{i} >= 18, person_each, 0)"
    options = ", ".join(f'"{o}"' for o in OPTIONS)
    option_labels = ", ".join(f'"{x}"' for x in BLOC_LABELS + ["Would not vote"])
    blocs = ", ".join(f'"{b}"' for b in BLOCS)
    bloc_labels = ", ".join(f'"{x}"' for x in BLOC_LABELS)
    ages = ", ".join(f'"{g[0]}"' for g in AGES)
    codes = ", ".join(f'"{c["code"]}"' for c in seats)
    names = ", ".join('"' + c["name"].replace('"', "'") + '"' for c in seats)
    age_labels = ", ".join(f'"{g[1]}"' for g in AGES)
    return f'''# The UK's voters (stage S5.2). GENERATED by tools/uk/voters.py; do not edit.
# Who votes for which bloc: the households' adults aged 18 and over in 600 voter types,
# with a multinomial logit over nine blocs and not voting (models/uk/politics/README.md).

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

[param.option_intercept]
doc = "Fitted so that the base month reproduces the 2024 general election in every region"
type = "real"
unit = "1"
dims = ["region", "option"]
data = "politics/intercepts.csv"

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
value = {a["income_effect"]!r}

[param.vote_unemployment_effect]
doc = "On the governing blocs' utility, per unit of unemployment rate above its level at the last election"
type = "real"
unit = "1"
value = {a["unemployment_effect"]!r}

[param.vote_inflation_effect]
doc = "On the governing blocs' utility, per unit of annual inflation above its level at the last election"
type = "real"
unit = "1"
value = {a["inflation_effect"]!r}

[param.vote_tenure_effect]
doc = "On the governing blocs' utility, per year in office"
type = "real"
unit = "1"
value = {a["tenure_effect"]!r}

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

[state.unemployment_at_election]
doc = "Unemployment at the last election; the base month's stands in for July 2024's (-1 until it is known)"
type = "real"
unit = "1"
phase = "politics"
initial = -1.0
next = "select(unemployment_at_election < 0.0 or election_now, unemployment_rate, unemployment_at_election)"

[state.inflation_at_election]
doc = "Inflation at the last election; the base month's stands in for July 2024's (-1 until it is known)"
type = "real"
unit = "1"
phase = "politics"
initial = -1.0
next = "select(inflation_at_election < -0.5 or election_now, inflation_annual, inflation_at_election)"

# ---- each household's change in real income, the pocketbook

[var.real_net_income]
type = "real"
unit = "GBP/month/household"
phase = "politics"
entity = "household"
expr = "net_income / price_index"

[state.income_memory]
doc = "Real net income, averaged over about a year (exponentially); 0 until the first month"
type = "real"
unit = "GBP/month/household"
phase = "politics"
entity = "household"
initial = 0.0
next = "select(income_memory > 0.0, income_memory + (real_net_income - income_memory) / 12.0, real_net_income)"

[var.income_change]
doc = "Real net income against its average over about a year"
type = "real"
unit = "1"
phase = "politics"
entity = "household"
expr = "select(income_memory > 0.0 and real_net_income > 0.0, real_net_income / income_memory - 1.0, 0.0)"

# ---- voter types

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
label = "The economy and time in office, on the government's utility"
type = "real"
unit = "1"
phase = "politics"
expr = "select(unemployment_at_election < 0.0, 0.0, vote_unemployment_effect * (unemployment_rate - unemployment_at_election)) + select(inflation_at_election < -0.5, 0.0, vote_inflation_effect * (inflation_annual - inflation_at_election)) + vote_tenure_effect * months_in_office / 12.0"

[var.utility]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type", "option"]
expr = "option_intercept[region: type_region] + option_age_effect[voter_age: type_age] + select(coord(option) < 9 and governing[bloc: min(coord(option), 8)], vote_income_effect * voter_income_change + fundamentals, 0.0)"

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
expr = "sum(select(type_region == coord(region), voters * choice[option: coord(bloc)], 0.0), voter_type) / sum(select(type_region == coord(region), voters * (1.0 - choice[option: abstain]), 0.0), voter_type)"

[var.government_support]
label = "Government's voting intention"
type = "real"
unit = "1"
phase = "politics"
expr = "sum(select(governing, vote_intention, 0.0), bloc)"

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
