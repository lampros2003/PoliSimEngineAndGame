"""Generate conformance/format1.tsv: format 1 formulas with the result the oracle gives.

    python tools/gen_conformance_format1.py

The same layout as conformance/cases.tsv (see tools/gen_conformance.py), evaluated
against models/cohort after three steps with seed 1. Formulas are national ("-") or per
town ("town"); dimensioned values are reached through sum(), indexing and the other
format 1 functions, so every case exercises gathers, coordinates, indexes, sums and
shifts. Curated cases cover the rules; random ones cover their combinations.
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "oracle"))
sys.path.insert(0, str(ROOT / "tools"))

from gen_conformance import expected  # noqa: E402
from polisim_oracle import Simulation, load_model  # noqa: E402

SEED = 1
WARM_UP_STEPS = 3
RANDOM_CASES = 900

DIMS = {"region": ["north", "midlands", "south"], "sex": ["female", "male"], "age": list(range(0, 101)),
        "band": list(range(16, 21))}
# name: (dimensions, type), unit person unless listed in RATES
VALUES = {
    "population": (("region", "sex", "age"), "real"),
    "deaths": (("region", "sex", "age"), "real"),
    "arrivals": (("region", "sex", "age"), "real"),
    "births": (("region", "sex"), "real"),
    "cohort_count": (("band",), "int"),
}
RATES = {
    "mortality": (("sex", "age"), "real"),
    "fertility": (("age",), "real"),
    "migration_rate": (("region",), "real"),
    "local_rate": (("region",), "real"),
}

CURATED = [
    # Stage S10.3: largest and smallest over dimensions.
    ("-", "real", "person", "largest(population, region, sex, age)"),
    ("-", "real", "person", "smallest(population, region, sex, age)"),
    ("-", "real", "person", "largest(population, age, sex, region)"),
    ("-", "real", "person", "sum(largest(population, age), region, sex)"),
    ("-", "real", "person", "largest(sum(population, age), region, sex)"),
    ("-", "int", "1", "largest(coord(age), age)"),
    ("-", "int", "1", "smallest(coord(age), age)"),
    ("-", "int", "1", "smallest(100 - coord(age), age)"),
    ("-", "int", "person", "largest(cohort_count, band)"),
    ("-", "int", "person", "smallest(cohort_count, band)"),
    ("-", "real", "1", "largest(mortality, sex, age) - smallest(mortality, sex, age)"),
    ("-", "real", "1", "largest(0.0 / 0.0 + coord(age), age)"),
    ("-", "real", "person", "largest(population, region, sex, region)"),
    ("-", "bool", "1", "largest(coord(age) > 3, age)"),
    ("-", "real", "person", "largest(population)"),
    # Stage S10.3: sum_by, ages grouped into bands of 25 years (band 16 to 20).
    ("-", "real", "person", "sum(sum_by(population, age, 16 + div(coord(age), 25), band), region, sex, band)"),
    ("-", "real", "person", "sum(select(coord(band) == 17, sum_by(population, age, 16 + div(coord(age), 25), band), 0.0), region, sex, band)"),
    ("-", "real", "person", "sum(select(coord(band) == 20, sum_by(population[region: south], age, 16 + div(coord(age), 25), band), 0.0), sex, band)"),
    ("-", "int", "1", "sum(sum_by(coord(age), age, 16 + div(coord(age), 25), band), band)"),
    ("-", "int", "1", "sum(select(coord(band) == 20, sum_by(coord(age), age, 16 + div(coord(age), 25), band), 0), band)"),
    ("-", "int", "1", "sum(select(coord(band) == 19, sum_by(1, age, 16 + mod(coord(age), 5), band), 0), band)"),
    ("-", "real", "1", "largest(sum_by(mortality, age, 16 + div(coord(age), 25), band), sex, band)"),
    ("-", "real", "person", "sum(sum_by(population, age, coord(age), band), region, sex, band)"),
    ("-", "real", "person", "sum_by(population, age, 16, band)"),
    ("-", "real", "person", "sum(sum_by(population, region, 16, band), band, region)"),
    ("-", "real", "person", "sum(sum_by(population, age, 16.0, band), region, sex, band)"),
    ("-", "real", "person", "sum(sum_by(population, age, cohort_count[band: 16], band), region, sex, band)"),
    ("-", "real", "person", "sum(sum_by(population[age: coord(band)], age, 16, band), region, sex, band)"),
    ("-", "real", "person", "sum(sum_by(coord(age) > 3, age, 16, band), band)"),
    ("-", "real", "person", "sum(population, region, sex, age)"),
    ("-", "real", "person", "sum(population, age, sex, region)"),
    ("-", "real", "person", "sum(sum(population, age), region, sex)"),
    ("-", "real", "person", "sum(sum(sum(population, age), sex), region)"),
    ("-", "int", "person", "sum(cohort_count, band)"),
    ("-", "int", "person", "sum(cohort_shift(cohort_count, band), band)"),
    ("-", "real", "person", "sum(cohort_shift(population, age), region, sex, age)"),
    ("-", "real", "person", "sum(cohort_shift(population, sex), region, sex, age)"),
    ("-", "real", "person", "sum(cohort_shift(population, region), region, sex, age)"),
    ("-", "int", "1", "sum(coord(age), age)"),
    ("-", "int", "1", "sum(coord(band) * coord(region), band, region)"),
    ("-", "real", "person", "population[region: south, sex: male, age: 0]"),
    ("-", "real", "person", "population[region: 2, sex: 1, age: 100]"),
    ("-", "real", "person", "population[age: 40, sex: female, region: midlands]"),
    ("-", "real", "person", "sum(population[sex: female], region, age)"),
    ("-", "real", "person", "sum(population[age: min(coord(age) + 1, 100)], region, sex, age)"),
    ("-", "real", "person", "sum(population[age: 100 - coord(age)], region, sex, age)"),
    ("-", "real", "person", "sum(births[sex: male], region)"),
    ("-", "real", "1", "sum(mortality * fertility, age, sex)"),
    ("-", "real", "person", "sum(select(coord(age) >= 65, population, 0.0), region, sex, age)"),
    ("-", "real", "person", "sum(population * mortality - deaths, region, sex, age)"),
    ("-", "real", "person", "sum(population - prev(population), region, sex, age)"),
    ("-", "real", "1", "sum(local_rate[region: coord(region)], region)"),
    ("-", "real", "town", "wsum(town, local_rate[region: region_code])"),
    ("town", "real", "1", "local_rate[region: region_code] * migration_rate[region: region_code]"),
    ("town", "real", "person", "population[region: region_code, sex: female, age: 30]"),
    ("town", "real", "person", "population[region: region_code, sex: region_code - region_code, age: region_code * 40]"),
    # grouped aggregates (S4.0)
    ("-", "real", "town", "sum(wsum_by(town, town_rate, region, region_code), region)"),
    ("-", "int", "town", "sum(wcount_by(town, town_rate > 0.2, region, region_code), region)"),
    ("-", "real", "town", "sum(wsum_by(town, local_rate[region: region_code], region, region_code) * coord(region), region)"),
    ("-", "int", "town", "sum(wsum_by(town, region_code, region, region_code), region)"),
    ("-", "real", "town", "sum(wsum_by(town, town_rate, region, 2 - region_code), region, sex)"),
    ("-", "real", "town", "sum(wsum_by(town, town_rate, region, region_code + 1), region)"),
    ("-", "real", "town", "wsum_by(town, town_rate, region, region_code)"),
    ("-", "real", "town", "sum(wsum_by(town, town_rate, region), region)"),
    ("-", "real", "town", "sum(wsum_by(town, town_rate, region, 0.5), region)"),
    ("town", "real", "town", "wsum_by(town, town_rate, region, region_code)"),
    ("-", "real", "town", "sum(wsum_by(nowhere, town_rate, region, region_code), region)"),
    ("-", "int", "town", "sum(wcount_by(town, town_rate, region, region_code), region)"),
    ("-", "real", "town", "sum(wsum_by(town, town_rate > 0.2, region, region_code), region)"),
    # run-time errors: coordinates outside their dimension
    ("-", "real", "person", "population[region: south, sex: male, age: 101]"),
    ("-", "real", "person", "population[region: 3, sex: male, age: 1]"),
    ("-", "real", "person", "sum(population[age: coord(age) + 1], region, sex, age)"),
    ("-", "int", "person", "cohort_count[band: 15]"),
    ("town", "real", "person", "population[region: region_code + 1, sex: male, age: 1]"),
    # rejected when compiled
    ("-", "real", "person", "population"),
    ("-", "real", "person", "sum(population, region, sex)"),
    ("-", "real", "person", "sum(population, age, age)"),
    ("-", "real", "person", "sum(sum(population, age), age, sex, region)"),
    ("-", "int", "1", "coord(age)"),
    ("-", "real", "person", "cohort_shift(population, age)"),
    ("-", "real", "person", "population[region: south, region: north, sex: male, age: 1]"),
    ("-", "real", "person", "population[height: 1, region: south, sex: male, age: 1]"),
    ("-", "real", "person", "population[region: south, sex: male, age: 1.0]"),
    ("-", "real", "person", "total_population[region: south]"),
    ("-", "real", "person", "sum(population, height)"),
    ("-", "real", "person", "sum(population)"),
    ("-", "real", "1", "sum(rand(noise), age)"),
    ("town", "real", "person", "sum(population, region, sex, age)"),
    ("town", "int", "1", "coord(region)"),
    ("-", "bool", "1", "sum(coord(age) > 3, age)"),
    ("-", "real", "person", "sum(population, region, sex, age) + sum(mortality, sex, age)"),
]


class Generator:
    """Random formulas over a scope of dimensions, typed and unit-correct most of the time."""

    def __init__(self, rng: random.Random):
        self.rng = rng

    def leaf(self, scope: tuple[str, ...], typ: str, unit: str) -> str:
        r = self.rng
        table = VALUES if unit == "person" else RATES
        options = [n for n, (dims, t) in table.items() if set(dims) <= set(scope) and (t == typ or typ == "real")]
        if unit == "1":
            options += [f"coord({d})" for d in scope] if typ in ("int", "real") else []
            options += ["boy_share", "ageing_share"] if typ == "real" else []
        else:
            options += ["cohort_entry"] if typ in ("int", "real") else []
            options += ["total_population"] if typ == "real" else []
        # An index: some dimensions fixed, the rest from the scope.
        for name, (dims, t) in table.items():
            if t == typ or typ == "real":
                free = [d for d in dims if d not in scope]
                fixed = free + [d for d in dims if d in scope and r.random() < 0.3]
                if fixed:
                    options.append(self.index(name, dims, fixed, scope))
        return r.choice(options) if options else ("0" if typ == "int" else "0.0")

    def coordinate(self, dim: str, scope: tuple[str, ...]) -> str:
        r, members = self.rng, DIMS[dim]
        choice = r.random()
        if isinstance(members[0], str) and choice < 0.5:
            return r.choice(members)
        if choice < 0.8 or dim not in scope:
            # a member number (range) or position (list), now and then just outside
            lo, hi = (members[0], members[-1]) if isinstance(members[0], int) else (0, len(members) - 1)
            return str(r.choice([lo, hi, r.randint(lo, hi), r.randint(lo, hi), hi + 1 if r.random() < 0.1 else lo]))
        span = len(members) - 1
        return r.choice([f"{span} - coord({dim})" if isinstance(members[0], int) and members[0] == 0 else f"coord({dim})",
                         f"min(coord({dim}) + 1, {members[-1] if isinstance(members[0], int) else span})"])

    def index(self, name: str, dims: tuple[str, ...], fixed: list[str], scope: tuple[str, ...]) -> str:
        order = list(fixed)
        self.rng.shuffle(order)
        return f"{name}[" + ", ".join(f"{d}: {self.coordinate(d, scope)}" for d in order) + "]"

    def expr(self, scope: tuple[str, ...], typ: str, unit: str, depth: int) -> str:
        r = self.rng
        if depth <= 0 or r.random() < 0.3:
            return self.leaf(scope, typ, unit)
        kind = r.random()
        if kind < 0.35:
            op = r.choice(["+", "-"])
            return f"({self.expr(scope, typ, unit, depth - 1)} {op} {self.expr(scope, typ, unit, depth - 1)})"
        if kind < 0.5 and unit == "person":
            return f"({self.expr(scope, typ, 'person', depth - 1)} * {self.expr(scope, 'real' if typ == 'real' else 'int', '1', depth - 1)})"
        if kind < 0.6:
            f = r.choice(["min", "max"])
            return f"{f}({self.expr(scope, typ, unit, depth - 1)}, {self.expr(scope, typ, unit, depth - 1)})"
        if kind < 0.7 and scope:
            d = r.choice(scope)
            k = r.choice(DIMS[d]) if isinstance(DIMS[d][0], int) else r.randrange(len(DIMS[d]))
            return f"select(coord({d}) >= {k}, {self.expr(scope, typ, unit, depth - 1)}, {self.expr(scope, typ, unit, depth - 1)})"
        if kind < 0.85 and scope:
            return f"cohort_shift({self.expr(scope, typ, unit, depth - 1)}, {r.choice(scope)})"
        if kind < 0.95:
            # a nested sum over some dimensions not yet in scope
            spare = [d for d in DIMS if d not in scope]
            if spare:
                over = r.sample(spare, r.randint(1, min(2, len(spare))))
                return f"sum({self.expr(scope + tuple(over), typ, unit, depth - 1)}, {', '.join(over)})"
        return self.leaf(scope, typ, unit)

    def national(self) -> tuple[str, str, str]:
        r = self.rng
        typ = r.choice(["real", "real", "int"])
        unit = r.choice(["person", "person", "1"])
        dims = r.sample(list(DIMS), r.randint(1, 3))
        inner = self.expr(tuple(dims), typ, unit, r.randint(1, 4))
        return "-", typ, unit, f"sum({inner}, {', '.join(dims)})"


def warmed_up_simulation() -> Simulation:
    sim = Simulation(load_model(ROOT / "models" / "cohort"), seed=SEED)
    sim.run(WARM_UP_STEPS)
    return sim


def main() -> None:
    rng = random.Random(20261115)
    generator = Generator(rng)
    cases = list(CURATED) + [generator.national() for _ in range(RANDOM_CASES)]
    sim = warmed_up_simulation()
    counts = {"value": 0, "E:static": 0, "E:runtime": 0}
    out = ROOT / "conformance" / "format1.tsv"
    with open(out, "w", encoding="utf-8", newline="") as handle:
        for ctx, typ, unit, formula in cases:
            assert "\t" not in formula and "\n" not in formula
            result = expected(sim, ctx, typ, unit, formula)
            counts[result if result.startswith("E:") else "value"] += 1
            handle.write(f"{ctx}\t{typ}\t{unit}\t{formula}\t{result}\n")
    print(f"wrote {out}: {len(cases)} cases, {counts}")


if __name__ == "__main__":
    main()
