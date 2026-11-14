"""Stage S10.7: random whole models, run by the oracle, for the engine to match.

Writes conformance/random_models.toml: models drawn at random from what format 1 offers
(phases, national values, records with their columns, sums and quantiles over them, values with
dimensions and their sums and indexes, states, prev, lags, situations, a flow between
two accounts, random draws and lever commands), each with the oracle's state hash after
every step, or the step at which the oracle stopped with an error. The engine runs each
on one, two and eight threads and must give the same hashes (crates/core/tests/
random_models.rs), so the cases test whole runs, the order of evaluation and the threads,
not single formulas.

Every formula reads only what has been declared before it and what its phase allows, and
every value is held within a million, so nearly every model runs; the few that stop, stop
in both. A model's records are not stored: both sides write the same file from the rule in
`records_csv`.

Run: python tools/gen_random_models.py
"""

from __future__ import annotations

import json
import random
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "oracle"))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

SEED = 107
MODELS = 80
STEPS = 8


def records_csv(n: int) -> str:
    """The records of every random model: whole-number arithmetic on the record's index,
    written as text both sides can produce exactly."""
    lines = ["id,weight,ci,cf,cb"]
    for i in range(n):
        v = (i * 7919) % 2001 - 1000
        cf = ("-" if v < 0 else "") + f"{abs(v) // 100}.{abs(v) % 100:02d}"
        lines.append(f"{i},{1 + (i * 31) % 5},{(i * 104729) % 23 - 11},{cf},{1 if (i * 13) % 3 == 0 else 0}")
    return "\n".join(lines) + "\n"


@dataclass
class Name:
    name: str
    type: str  # real, int, bool
    scope: str  # nat, rec, d1 (dims d1), d12 (dims d1 and d2)
    phase: int  # the phase it is computed in; -1 for what any phase may read
    prev: bool = False  # may be read through prev()


HEADER = """[model]
id = "random{k}"
format = 1
currency = "GBP"
minor_units = 100
step = "month"
phases = [{phases}]

[dim.d1]
members = ["a", "b", "c"]

[dim.d2]
range = [0, 3]

[entity.rec]
data = "rec.csv"
id = "id"
weight = "weight"

[entity.rec.columns.ci]
type = "int"
unit = "1"

[entity.rec.columns.cf]
type = "real"
unit = "1"

[entity.rec.columns.cb]
type = "bool"

[stream.s1]

[param.k1]
type = "real"
unit = "1"
value = 0.37

[param.k2]
type = "int"
unit = "1"
value = 3

[lever.lv]
type = "real"
unit = "1"
default = 0.5
range = [-10.0, 10.0]

[sector.gov]

[sector.firms]

[instrument.cash]
unit = "GBP"
issuer = "gov"

[account.gov_cash]
sector = "gov"
instrument = "cash"

[account.firms_cash]
sector = "firms"
instrument = "cash"
initial = 0

[param.fee]
type = "money"
unit = "GBP/month"
value = 1.25

[table.rc]
kind = "curve"
x_unit = "1"
unit = "1"
points = [{{ x = "-10.0", y = "-3.0" }}, {{ x = "0.0", y = "0.0" }}, {{ x = "k1", y = "1.0" }}, {{ x = "50.0", y = "2.0" }}]

[state.tick]
type = "int"
unit = "1"
phase = "p0"
initial = 0
next = "tick + 1"
"""

READS = {"nat": ("nat",), "rec": ("nat", "rec"), "d1": ("nat", "d1"), "d12": ("nat", "d1", "d12")}
LIMIT = {"real": "-1000000.0, 1000000.0", "int": "-1000000, 1000000"}


class Model:
    def __init__(self, rng: random.Random, k: int):
        self.rng = rng
        self.phases = rng.randint(1, 3)
        self.names: list[Name] = [
            Name("k1", "real", "nat", -1), Name("k2", "int", "nat", -1), Name("lv", "real", "nat", -1),
            Name("ci", "int", "rec", -1), Name("cf", "real", "rec", -1), Name("cb", "bool", "rec", -1),
            Name("tick", "int", "nat", -1, True),
        ]
        self.parts = [HEADER.format(k=k, phases=", ".join(f'"p{i}"' for i in range(self.phases)))]
        self.count = 0

    # ---- expressions

    def readable(self, typ: str, scope: str, phase: int, prev: bool = False) -> list[str]:
        return [n.name for n in self.names
                if n.type == typ and n.scope in READS[scope] and n.phase <= phase and (n.prev or not prev)]

    def leaf(self, typ: str, scope: str, phase: int) -> str:
        rng = self.rng
        names = self.readable(typ, scope, phase)
        if typ == "bool":
            return rng.choice(names) if names and rng.random() < 0.8 else rng.choice(["true", "false"])
        extra = []
        if scope in ("d1", "d12"):
            extra.append("coord(d1)")
        if scope == "d12":
            extra.append("coord(d2)")
        if typ == "real":
            names += self.readable("int", scope, phase)
            if scope in ("rec", "nat") and rng.random() < 0.15:
                return "rand(s1)"
            literals = ["0.0", "1.0", "-2.5", "0.37", "0.001", "100.0"]
        else:
            literals = ["0", "1", "2", "-3", "7", "100"]
        if (names or extra) and rng.random() < 0.75:
            return rng.choice(names + extra)
        return rng.choice(literals)

    def expr(self, typ: str, scope: str, phase: int, depth: int) -> str:
        rng = self.rng
        if depth <= 0 or rng.random() < 0.25:
            return self.leaf(typ, scope, phase)
        e = lambda t: self.expr(t, scope, phase, depth - 1)  # noqa: E731
        if typ == "real":
            forms = [
                lambda: f"({e('real')} + {e('real')})", lambda: f"({e('real')} - {e('real')})",
                lambda: f"({e('real')} * {e('real')})", lambda: f"safe_div({e('real')}, {e('real')}, 0.0)",
                lambda: f"min({e('real')}, {e('real')})", lambda: f"max({e('real')}, {e('real')})",
                lambda: f"clamp({e('real')}, -100.0, 100.0)", lambda: f"select({e('bool')}, {e('real')}, {e('real')})",
                lambda: f"abs({e('real')})", lambda: f"exp(clamp({e('real')}, -5.0, 5.0))",
                lambda: f"ln(1.0 + abs({e('real')}))", lambda: f"sqrt(abs({e('real')}))",
                lambda: f"pow(1.0 + abs(clamp({e('real')}, -1.0, 1.0)), clamp({e('real')}, -3.0, 3.0))",
                lambda: f"pow({e('real')}, 2)", lambda: f"({e('real')} / 4.0)",
                lambda: f"curve({e('real')}, rc)",
            ]
            previous = self.readable("real", scope, 10, prev=True)
            if previous:
                forms.append(lambda: f"prev({rng.choice(previous)})")
            if scope == "nat":
                # Sums over records and over dimensions, weighted up: they are what run on
                # several threads.
                forms += [lambda: f"safe_div(wsum(rec, {self.expr('real', 'rec', phase, depth - 1)}), "
                                  f"wcount(rec, true), 0.0)"] * 3
                forms.append(lambda: f"safe_div(wcount(rec, {self.expr('bool', 'rec', phase, depth - 1)}), "
                                     f"wcount(rec, true), 0.0)")
                forms += [lambda: f"quantile(rec, {self.expr('real', 'rec', phase, depth - 1)}, "
                                  f"{rng.choice(['0.0', '0.1', '0.5', '0.9', '1.0', 'clamp(abs(k1), 0.0, 1.0)'])})"] * 2
                ones = self.readable("real", "d1", phase)
                ones = [n for n in ones if self.scope_of(n) == "d1"]
                twos = [n for n in self.readable("real", "d12", phase) if self.scope_of(n) == "d12"]
                if ones:
                    forms += [lambda: f"sum({rng.choice(ones)}, d1)", lambda: f"{rng.choice(ones)}[d1: b]",
                              lambda: f"largest({rng.choice(ones)}, d1)"] * 2
                if twos:
                    forms += [lambda: f"sum({rng.choice(twos)}, d1, d2)"] * 3
            if scope == "d1":
                twos = [n for n in self.readable("real", "d12", phase) if self.scope_of(n) == "d12"]
                if twos:
                    forms.append(lambda: f"sum({rng.choice(twos)}, d2)")
            return rng.choice(forms)()
        if typ == "int":
            forms = [
                lambda: f"({e('int')} + {e('int')})", lambda: f"({e('int')} - {e('int')})",
                lambda: f"({e('int')} * {rng.choice(['2', '3', '-1'])})", lambda: f"div({e('int')}, 3)",
                lambda: f"mod({e('int')}, 7)", lambda: f"min({e('int')}, {e('int')})",
                lambda: f"max({e('int')}, {e('int')})", lambda: f"abs({e('int')})",
                lambda: f"select({e('bool')}, {e('int')}, {e('int')})",
                lambda: f"round(clamp({e('real')}, {LIMIT['real']}))",
                lambda: f"floor(clamp({e('real')}, {LIMIT['real']}))",
            ]
            previous = self.readable("int", scope, 10, prev=True)
            if previous:
                forms.append(lambda: f"prev({rng.choice(previous)})")
            return rng.choice(forms)()
        forms = [
            lambda: f"({e('real')} > {e('real')})", lambda: f"({e('int')} == {e('int')})",
            lambda: f"({e('int')} <= {e('int')})", lambda: f"({e('bool')} and {e('bool')})",
            lambda: f"({e('bool')} or {e('bool')})", lambda: f"(not {e('bool')})",
        ]
        return rng.choice(forms)()

    def scope_of(self, name: str) -> str:
        return next(n.scope for n in self.names if n.name == name)

    def bounded(self, typ: str, scope: str, phase: int) -> str:
        body = self.expr(typ, scope, phase, self.rng.randint(1, 3))
        return body if typ == "bool" else f"clamp({body}, {LIMIT[typ]})"

    # ---- elements

    def shape(self, scope: str) -> str:
        return {"nat": "", "rec": 'entity = "rec"\n', "d1": 'dims = ["d1"]\n', "d12": 'dims = ["d1", "d2"]\n'}[scope]

    def add(self) -> None:
        rng = self.rng
        self.count += 1
        name = f"e{self.count}"
        typ = rng.choice(["real", "real", "real", "int", "bool"])
        scope = rng.choice(["nat", "nat", "rec", "rec", "d1", "d12"])
        if scope.startswith("d"):
            typ = "real"
        phase = rng.randrange(self.phases)
        unit = "" if typ == "bool" else 'unit = "1"\n'
        initial = {"real": "0.25", "int": "1", "bool": "false"}[typ]
        kind = rng.choice(["var", "var", "var", "state", "lag", "situation"])
        if kind == "lag":
            targets = [n for n in self.names if n.phase >= 0 and n.type != "bool" and n.scope != "d12"]
            if not targets:
                kind = "var"
            else:
                of = rng.choice(targets)
                start = {"real": "0.0", "int": "0"}[of.type]
                self.parts.append(f"[lag.{name}]\nof = \"{of.name}\"\nsteps = {rng.randint(1, 4)}\ninitial = {start}\n")
                self.names.append(Name(name, of.type, of.scope, 0, True))
                return
        if kind == "situation":
            start = self.expr("bool", "nat", self.phases - 1, 2)
            end = f'end = "{self.expr("bool", "nat", self.phases - 1, 2)}"\n' if rng.random() < 0.5 else ""
            self.parts.append(f"[situation.{name}]\nstart = \"{start}\"\n{end}")
            self.names.append(Name(name, "bool", "nat", -1))
            return
        if kind == "state":
            body = self.bounded(typ, scope, phase)
            self.parts.append(f"[state.{name}]\ntype = \"{typ}\"\n{unit}{self.shape(scope)}phase = \"p{phase}\"\n"
                              f"initial = {initial}\nnext = \"{body}\"\n")
            self.names.append(Name(name, typ, scope, -1, True))
            return
        body = self.bounded(typ, scope, phase)
        self.parts.append(f"[var.{name}]\ntype = \"{typ}\"\n{unit}{self.shape(scope)}phase = \"p{phase}\"\n"
                          f"initial = {initial}\nexpr = \"{body}\"\n")
        self.names.append(Name(name, typ, scope, phase, True))
        # So that the state hash covers every var: a state that keeps its value.
        self.parts.append(f"[state.{name}_kept]\ntype = \"{typ}\"\n{unit}{self.shape(scope)}"
                          f"phase = \"p{self.phases - 1}\"\ninitial = {initial}\nnext = \"{name}\"\n")

    def fragile(self) -> None:
        """A var that stores an infinity, and so stops the run, in a chosen step: for the
        nation, or for the records (at the first step where some record's ci meets it)."""
        rng = self.rng
        self.count += 1
        at = rng.randint(1, STEPS + 2)
        scope = rng.choice(["nat", "rec"])
        body = f"1.0 / (tick - {at})" if scope == "nat" else f"1.0 / (ci + tick - {at + 11})"
        self.parts.append(f"[var.e{self.count}]\ntype = \"real\"\nunit = \"1\"\n{self.shape(scope)}"
                          f"phase = \"p{rng.randrange(self.phases)}\"\nexpr = \"{body}\"\n")

    def text(self) -> str:
        last = self.phases - 1
        flow = (f"[flow.pay]\nfrom = \"gov\"\nto = \"firms\"\nphase = \"p{last}\"\n"
                f"expr = \"round(fee * clamp({self.expr('real', 'nat', last, 2)}, 0.0, 1000.0))\"\n")
        return "\n".join(self.parts + [flow])


def outcome(text: str, records: int, seed: int, commands: dict) -> tuple[list[str], tuple | None] | None:
    """The oracle's hashes after each step and the step that failed with its message, if
    one did; None if the oracle refuses the model."""
    with tempfile.TemporaryDirectory() as folder:
        (Path(folder) / "model.toml").write_text(text, encoding="utf-8", newline="\n")
        (Path(folder) / "rec.csv").write_text(records_csv(records), encoding="utf-8", newline="\n")
        try:
            sim = Simulation(load_model(Path(folder)), seed=seed, commands=commands)
        except (ModelError, FormulaError, SimError):
            return None
        hashes = []
        for step in range(STEPS):
            try:
                hashes.append(sim.step()["hash"])
            except SimError as exc:
                return hashes, (step, str(exc))
        return hashes, None


def main() -> None:
    rng = random.Random(SEED)
    out = ["# Stage S10.7: random whole models and the oracle's state hash after each step",
           "# (tools/gen_random_models.py, which explains them). The engine must give the same",
           "# hashes on one, two and eight threads (crates/core/tests/random_models.rs).",
           "# Regenerate only on purpose.", ""]
    made = refused = failed = 0
    k = 0
    while made < MODELS:
        k += 1
        model = Model(rng, k)
        for _ in range(rng.randint(4, 18)):
            model.add()
            if rng.random() < 0.02:
                model.fragile()
        text = model.text()
        records = rng.choice([1, 7, 40, 300, 5000])
        seed = rng.randrange(1 << 32)
        commands: dict[int, dict] = {}
        for _ in range(rng.randint(0, 2)):
            commands.setdefault(rng.randrange(STEPS), {})["lv"] = round(rng.uniform(-10.0, 10.0), 3)
        result = outcome(text, records, seed, commands)
        if result is None:
            refused += 1
            continue
        hashes, error = result
        made += 1
        failed += error is not None
        assert "'''" not in text
        listed = ", ".join(f'[{step}, "lv", {value!r}]' for step, levers in sorted(commands.items())
                           for value in levers.values())
        out += ["[[model]]", f'name = "random{k}"', f"records = {records}", f"seed = {seed}",
                f"steps = {STEPS}", f"commands = [{listed}]"]
        if error is not None:
            out += [f"error_at = {error[0]}", f"error = {json.dumps(error[1])}"]
        out += ["hashes = [" + ", ".join(f'"{h}"' for h in hashes) + "]", f"text = '''\n{text}'''", ""]
    path = ROOT / "conformance" / "random_models.toml"
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"wrote {path}: {made} models ({failed} stop with an error), {refused} refused and redrawn")


if __name__ == "__main__":
    main()
