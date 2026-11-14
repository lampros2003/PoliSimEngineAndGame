"""The reference step loop. Executable definition of docs/spec/00-engine-contract.md.

One step:
  1. apply the commands scheduled for this step (lever changes);
  2. for each phase in order: evaluate its vars and flows in dependency order, then
     evaluate and commit the `next` value of every state updated in that phase;
  3. post every flow to the accounts (double entry);
  4. verify the accounting identities and declared ranges;
  5. keep this step's values for prev(), and hash the persistent state.

Accounts are read at their start-of-step value throughout a step. A state is read at its
new value only by phases after the one that updates it.
"""

from __future__ import annotations

import hashlib
import struct

from .expr import SimError, compile_formula
from .model import Model, ModelError, Scenario, convert
from . import units as U
from .units import parse_unit


class Runtime:
    """Values the compiled formulas read. The dict objects are never replaced."""

    def __init__(self, seed: int):
        self.S: dict[str, object] = {}  # current scalars
        self.C: dict[str, list] = {}  # current per-record columns
        self.PS: dict[str, object] = {}  # scalars at the end of the previous step
        self.PC: dict[str, list] = {}  # columns at the end of the previous step
        self.W: dict[str, list[int]] = {}  # each entity's current weights, updated in place
        self.generation = 0  # changes before each evaluation of a formula (see expr._per_member)
        self.seed = seed
        self.step = 0  # index of the step being computed


class Simulation:
    def __init__(self, model: Model, seed: int = 0, preset: str = "central",
                 params: dict | None = None, levers: dict | None = None,
                 commands: dict[int, dict] | None = None):
        self.model = model
        self.rt = rt = Runtime(seed)
        self.commands = commands or {}
        self.flow_totals: dict[str, int] = {}
        self.votes: list[dict] = []  # format 1 (S5.4): every vote on a lever change
        self.defeated = 0  # bills defeated in the step being computed
        self.spent = 0.0  # stage S12.4: political capital the step's bills have spent so far
        m, minor = model, model.minor
        sym = m.symbols
        for name, entity in m.entities.items():
            rt.W[name] = list(entity.weights)

        # ---- parameters, levers, data columns
        overrides = dict(params or {})
        for d in sym.values():
            if d.kind == "param":
                what = f"param {d.name}"
                if d.name in overrides:
                    raw = overrides.pop(d.name)
                elif d.dims and "data" in d.spec:
                    columns = d.spec.get("columns")
                    if isinstance(columns, dict):
                        if preset not in columns:
                            raise ModelError(f"{what}: no column for the {preset!r} preset")
                        column = columns[preset]
                    else:
                        column = d.spec.get("column", "value")
                    rt.C[d.name] = self._checked(d, [convert(t, d.type, d.money, minor, what) for t in d.data[column]])
                    continue
                elif "value" in d.spec:
                    raw = d.spec["value"]
                elif preset in d.spec:
                    raw = d.spec[preset]
                else:
                    raise ModelError(f"param {d.name}: no 'value' and no {preset!r} preset")
                value = convert(raw, d.type, d.money, minor, what)
                if d.dims:
                    rt.C[d.name] = self._checked(d, [value] * len(m.cells(d.dims)))
                else:
                    rt.S[d.name] = self._checked(d, value)
            elif d.kind == "column":
                texts = m.entities[d.entity].raw[d.name]
                rt.C[d.name] = [convert(t, d.type, d.money, minor, f"column {d.name}") for t in texts]
        if overrides:
            raise ModelError(f"unknown parameter(s): {', '.join(overrides)}")
        lever_overrides = dict(levers or {})
        for d in sym.values():
            if d.kind == "lever":
                if d.spec.get("dilemma") and d.name in lever_overrides:
                    raise ModelError(f"dilemma {d.name}: it is answered by a command, not set at the start")
                self._set_lever(d.name, lever_overrides.pop(d.name, d.initial))
        if lever_overrides:
            raise ModelError(f"unknown lever(s): {', '.join(lever_overrides)}")

        # ---- initial state: states and holders' accounts, then issuers' accounts
        def initial(d):
            what = f"{d.kind} {d.name} initial"
            if d.dims:
                if isinstance(d.initial, dict):
                    texts = d.data[d.initial.get("column", "value")]
                    return [convert(t, d.type, d.money, minor, what) for t in texts]
                return [convert(d.initial, d.type, d.money, minor, what)] * len(m.cells(d.dims))
            if d.entity is None:
                return convert(d.initial, d.type, d.money, minor, what)
            entity = m.entities[d.entity]
            if isinstance(d.initial, dict):
                texts = entity.raw[d.initial["column"]]
                return [convert(t, d.type, d.money, minor, what) for t in texts]
            return [convert(d.initial, d.type, d.money, minor, what)] * len(entity.ids)

        for d in sym.values():
            if d.kind == "state" or (d.kind == "account" and d.initial is not None):
                self._store(d, initial(d))
        self._sync_weights()
        for instrument, info in m.instruments.items():
            held = sum(self._total(sym[name]) for (sector, ins), name in m.accounts.items()
                       if ins == instrument and sector != info["issuer"])
            issuer = m.accounts[(info["issuer"], instrument)]
            self._store(sym[issuer], self._int64(-held, f"account {issuer}"))

        # ---- compile formulas and build the evaluation plan
        self.cells = {d.name: m.cells(d.dims) for d in sym.values() if d.dims and d.expr is not None}
        self.fn: dict[str, object] = {}
        deps: dict[str, set[str]] = {}
        self.lagged: set[str] = set()
        for d in sym.values():
            if d.expr is None:
                continue
            label = f"{d.kind} {d.name}" + (" (next)" if d.kind == "state" else "")
            self.fn[d.name], deps[d.name], lagged = compile_formula(
                d.expr, m, rt, d.entity, d.type, d.unit, label, d.dims)
            self.lagged |= lagged
        self.weight_states = {e.weight_state for e in m.entities.values() if e.weight_state}
        self.rakes: dict[str, object] = {}
        for d in sym.values():
            if d.rake is not None:
                self.rakes[d.name], deps[d.name], lagged = self._compile_rake(d)
                self.lagged |= lagged
        self.plan = self._plan(deps)

        # ---- values that prev() sees during the first step
        for name in sorted(self.lagged):
            d = sym[name]
            if d.kind in ("var", "flow"):
                if d.initial is None:
                    raise ModelError(f"{d.kind} {name} is read through prev() and needs 'initial'")
                self._store(d, initial(d))
        self._remember()
        self.steps_done = 0

    # ------------------------------------------------------------------ helpers

    def _checked(self, d, value):
        """Type-level and declared-range checks on one value or one column."""
        for v in (value if isinstance(value, list) else (value,)):
            if d.type == "real" and (v != v or v in (float("inf"), float("-inf"))):
                raise SimError(f"{d.kind} {d.name}: value is not finite")
            if d.range is not None and not (d.range[0] <= float(v) <= d.range[1]):
                shown = v / self.model.minor if d.money else v
                raise SimError(f"{d.kind} {d.name}: {shown} is outside its declared range")
        return value

    def _store(self, d, value) -> None:
        (self.rt.S if d.entity is None and not d.dims else self.rt.C)[d.name] = self._checked(d, value)

    def _total(self, d) -> int:
        """Sector-level total of a scalar or per-record whole-number quantity."""
        if d.entity is None:
            return self.rt.S[d.name]
        weights = self.rt.W[d.entity]
        return sum(w * v for w, v in zip(weights, self.rt.C[d.name]))

    def _sync_weights(self) -> None:
        """Format 1 (S4.4): copy weight states into the weights every aggregate reads."""
        for name, entity in self.model.entities.items():
            if entity.weight_state is not None:
                values = self.rt.C[entity.weight_state]
                if min(values) < 1:
                    raise SimError(f"state {entity.weight_state}: weights must be whole numbers of at least 1")
                self.rt.W[name][:] = values

    def _compile_rake(self, d):
        """Format 1 (S4.4): a weight state's rake (docs/spec/06-model-format-1.md). Returns
        a function giving the new weights, the names it reads and those read through prev()."""
        m, rt, rake = self.model, self.rt, d.rake
        what = f"state {d.name} rake"
        count = len(m.entities[d.entity].ids)
        when, deps, lagged = compile_formula(rake.when, m, rt, None, "bool", parse_unit("1"), f"{what} when")
        margins = []
        for k, margin in enumerate(rake.margins):
            t = m.symbols[margin.target]
            deps.add(t.name)
            dims = [m.dims[n] for n in t.dims]
            strides, stride = [], 1
            for D in reversed(dims):
                strides.append(stride)
                stride *= D.size
            strides.reverse()
            per_record = U.div(t.unit, ((d.entity, 1),))
            slots = []
            for slot in margin.slots:
                where = f"{what} margin {k + 1}"
                fn, used, lag = compile_formula(slot.count, m, rt, d.entity, "real", per_record, f"{where} count")
                deps |= used
                lagged |= lag
                ats = []
                for D, src in zip(dims, slot.at):
                    at, used, lag = compile_formula(src, m, rt, d.entity, "int", U.ONE, f"{where} at {D.name}")
                    deps |= used
                    lagged |= lag
                    ats.append(at)
                slots.append((fn, ats))
            margins.append((t.name, dims, strides, stride, slots))

        def run():
            if not when(0):
                return list(rt.C[d.name])
            prepared = []
            for target, dims, strides, cells, slots in margins:
                values = rt.C[target]
                for x in values:
                    if x != x or x in (float("inf"), float("-inf")) or x < 0:
                        raise SimError(f"{what}: a cell of the target {target} is {x}, not a finite number of at least 0")
                evaluated = []
                for fn, ats in slots:
                    counts = [fn(r) for r in range(count)]
                    evaluated.append((counts, [[at(r) for r in range(count)] for at in ats]))
                pairs = [[] for _ in range(cells)]
                for r in range(count):
                    for counts, ats in evaluated:
                        c = counts[r]
                        if c != c or c in (float("inf"), float("-inf")) or c < 0:
                            raise SimError(f"{what}: a record's count is {c}, not a finite number of at least 0")
                        if c == 0:
                            continue
                        flat = 0
                        for D, stride, at in zip(dims, strides, ats):
                            v = at[r]
                            pos = v - (D.first if D.kind == "range" else 0)
                            if not 0 <= pos < D.size:
                                raise SimError(f"{what}: a record's member {v} is not in {D.name}")
                            flat += pos * stride
                        pairs[flat].append((r, float(c)))
                prepared.append((values, pairs))
            v = [float(w) for w in rt.C[d.name]]
            for _ in range(rake.passes):
                for values, pairs in prepared:
                    for cell, members in enumerate(pairs):
                        total = 0.0
                        for r, c in members:
                            total = total + v[r] * c
                        goal = float(values[cell])
                        if total > 0.0 and goal > 0.0:
                            f = goal / total
                            last = -1
                            for r, _ in members:
                                if r != last:
                                    v[r] = v[r] * f
                                    last = r
            out = []
            for x in v:
                if x != x or x in (float("inf"), float("-inf")):
                    raise SimError(f"{what}: a weight is not finite")
                w = round(x)
                if not -(1 << 63) <= w < (1 << 63):
                    raise SimError(f"{what}: a weight does not fit in 64 bits")
                out.append(max(w, 1))
            return out
        return run, deps, lagged

    def _passes(self, name: str, raw) -> bool:
        """Format 1 (S5.4): a change to a lever with a leaning is a bill. The leading bloc (the
        governing bloc with the most seats, the first on a tie) votes for it; every other bloc
        votes for it if the move is towards it from the leader's position (from 0 with no
        leader): a move to the left if its position is lower, to the right if higher. It
        passes with more than half the seats. Every vote is kept in `votes`."""
        m, rt = self.model, self.rt
        d = m.symbols.get(name)
        if m.legislature is None or d is None or d.kind != "lever" or "leaning" not in d.spec:
            return True
        new = convert(raw, d.type, d.money, m.minor, f"lever {name}")
        old = rt.S[name]
        if new == old:
            return True
        left = (new > old) == (d.spec["leaning"] == "left")
        seats, governing = rt.C[m.legislature["seats"]], rt.C[m.legislature["governing"]]
        position = rt.C[m.legislature["position"]]
        everyone = sum(seats)
        # Stage S12.4: a bill costs political capital; one that costs more than is left is
        # refused before any vote.
        cost = None
        if "capital" in m.legislature:
            cost = self._bill_cost(d, new, old)
            if cost > rt.S[m.legislature["capital"]] - self.spent:
                self.votes.append({"step": rt.step, "lever": name, "value": new, "for": 0, "seats": everyone,
                                   "passed": False, "cost": cost, "refused": True})
                return False
        leader, most = -1, None
        for b, (n, g) in enumerate(zip(seats, governing)):
            if g and (most is None or n > most):
                leader, most = b, n
        here = position[leader] if leader >= 0 else 0.0
        votes_for = sum(n for b, (n, p) in enumerate(zip(seats, position))
                        if b == leader or (p < here if left else p > here))
        passed = 2 * votes_for > everyone
        self.votes.append({"step": rt.step, "lever": name, "value": new, "for": votes_for, "seats": everyone,
                           "passed": passed, "cost": cost, "refused": False})
        if not passed:
            self.defeated += 1
        elif cost is not None:
            self.spent = self.spent + cost
        return passed

    def _bill_cost(self, d, new, old) -> float:
        """Stage S12.4: `bill_cost + swing_cost * capital_weight * abs(new - old) / (max - min)`,
        left to right in real numbers; a lever without a range costs `bill_cost`."""
        leg, S = self.model.legislature, self.rt.S
        cost = S[leg["bill_cost"]]
        if d.range is None or not d.range[1] > d.range[0]:
            return cost
        moved = float(abs(new - old))
        weight = float(d.spec.get("capital_weight", 1.0))
        return cost + S[leg["swing_cost"]] * weight * (moved / (d.range[1] - d.range[0]))

    def _check_answer(self, name: str, raw) -> None:
        """Stage S9.1: an answer to a dilemma is a whole number from 1 to the number of its
        answers, given while it is open (at the start of the step)."""
        d = self.model.symbols.get(name)
        if d is None or d.kind != "lever" or not d.spec.get("dilemma"):
            return
        if not self.rt.S[f"{name}_open"]:
            raise SimError(f"dilemma {name} is not open")
        value = convert(raw, d.type, d.money, self.model.minor, f"dilemma {name}")
        count = d.spec["range"][1]
        if not 1 <= value <= count:
            raise SimError(f"dilemma {name}: the answer must be from 1 to {count}")

    def _set_lever(self, name: str, raw) -> None:
        d = self.model.symbols.get(name)
        if d is None or d.kind != "lever":
            raise ModelError(f"{name!r} is not a lever")
        self._store(d, convert(raw, d.type, d.money, self.model.minor, f"lever {name}"))

    def _remember(self) -> None:
        rt = self.rt
        rt.PS.clear()
        rt.PS.update(rt.S)
        rt.PC.clear()
        rt.PC.update(rt.C)  # columns are replaced, never mutated, so sharing is safe

    def _plan(self, deps: dict[str, set[str]]):
        """Per phase: vars and flows in dependency order, then the states updated there."""
        sym, phases = self.model.symbols, self.model.phases
        plan = []
        for p in range(len(phases)):
            members = [d.name for d in sym.values() if d.kind in ("var", "flow") and d.phase == p]
            states = [d.name for d in sym.values() if d.kind == "state" and d.phase == p]
            for name in members + states:
                for used in deps[name]:
                    u = sym[used]
                    if u.kind in ("var", "flow") and u.phase > p:
                        raise ModelError(
                            f"{name} (phase {phases[p]}) reads {used}, which is computed later "
                            f"(phase {phases[u.phase]}); use prev({used}) or move it")
            order, placed, remaining = [], set(), list(members)
            while remaining:
                ready = [n for n in remaining
                         if all(u in placed or u not in members for u in deps[n])]
                if not ready:
                    raise ModelError(f"circular dependency in phase {phases[p]}: {', '.join(remaining)}")
                order.append(ready[0])  # earliest declared among those that are ready
                placed.add(ready[0])
                remaining.remove(ready[0])
            plan.append((order, states))
        return plan

    def _evaluate(self, d):
        self.rt.generation += 1
        if d.name in self.rakes:
            return self.rakes[d.name]()
        fn = self.fn[d.name]
        if d.dims:
            return [fn(cell) for cell in self.cells[d.name]]
        if d.entity is None:
            return fn(0)
        return [fn(i) for i in range(len(self.model.entities[d.entity].ids))]

    # ------------------------------------------------------------------ the step

    def step(self) -> dict:
        m, rt, sym = self.model, self.rt, self.model.symbols
        try:
            self.defeated = 0
            self.spent = 0.0
            leg = m.legislature or {}
            for name, raw in self.commands.get(rt.step, {}).items():
                if name == leg.get("spent"):
                    raise SimError(f"lever {name}: the engine sets it (the capital bills spent)")
                self._check_answer(name, raw)
                if self._passes(name, raw):
                    self._set_lever(name, raw)
            if "spent" in leg:
                self._store(sym[leg["spent"]], self.spent)

            for order, states in self.plan:
                for name in order:
                    self._store(sym[name], self._evaluate(sym[name]))
                pending = [(sym[name], self._evaluate(sym[name])) for name in states]
                for d, value in pending:
                    self._store(d, value)
                if any(d.name in self.weight_states for d, _ in pending):
                    self._sync_weights()

            self._post_flows()
            # Stage S9.1: an answer to a dilemma lasts one step; between steps its lever is 0.
            for dilemma in m.dilemmas:
                self._store(sym[dilemma["name"]], 0)
        except SimError as exc:
            raise SimError(f"step {rt.step}: {exc}") from None

        self._remember()
        self.steps_done += 1
        rt.step += 1
        return self.record()

    def _post_flows(self) -> None:
        m, rt, sym = self.model, self.rt, self.model.symbols
        scalars = {name: rt.S[name] for name in m.accounts.values() if sym[name].entity is None}
        columns = {name: list(rt.C[name]) for name in m.accounts.values() if sym[name].entity is not None}
        before = {name: self._total(sym[name]) for name in m.accounts.values()}
        net = dict.fromkeys(m.accounts.values(), 0)

        for flow in m.flows.values():
            d = sym[flow.name]
            src, dst = m.accounts[(flow.src, flow.instrument)], m.accounts[(flow.dst, flow.instrument)]
            if d.entity is None:
                total = rt.S[flow.name]
                if total < 0:
                    raise SimError(f"flow {flow.name} is negative")
                amounts = None
            else:
                amounts = rt.C[flow.name]
                if min(amounts) < 0:
                    raise SimError(f"flow {flow.name} is negative for at least one record")
                total = sum(w * a for w, a in zip(rt.W[d.entity], amounts))
            self._int64(total, f"flow {flow.name}")
            # Flows are applied in declaration order and every intermediate balance must fit.
            for account, sign in ((src, -1), (dst, 1)):
                if sym[account].entity is None:
                    scalars[account] = self._int64(scalars[account] + sign * total, account)
                else:
                    column = columns[account]
                    for i, amount in enumerate(amounts):
                        column[i] = self._int64(column[i] + sign * amount, account)
                net[account] += sign * total
            self.flow_totals[flow.name] = total

        for name, value in scalars.items():
            self._store(sym[name], value)
        for name, column in columns.items():
            self._store(sym[name], column)

        # Identities. They hold by construction here; the engine must reproduce them.
        for name in m.accounts.values():
            if self._int64(self._total(sym[name]), name) != before[name] + net[name]:
                raise SimError(f"account {name}: balance change differs from its net flows")
        for instrument in m.instruments:
            total = sum(self._total(sym[name]) for (_, ins), name in m.accounts.items() if ins == instrument)
            if total != 0:
                raise SimError(f"instrument {instrument}: balances sum to {total}, not zero")

    @staticmethod
    def _int64(value: int, name: str) -> int:
        if not -(1 << 63) <= value < (1 << 63):
            raise SimError(f"{name}: value does not fit in 64 bits")
        return value

    # ------------------------------------------------------------------ outputs

    def run(self, steps: int) -> list[dict]:
        return [self.step() for _ in range(steps)]

    def record(self) -> dict:
        """One row of results for the step just completed: every scalar plus sector totals."""
        sym, rt = self.model.symbols, self.rt
        row: dict[str, object] = {"step": rt.step - 1, "hash": self.state_hash()}
        for d in sym.values():
            if d.kind == "param" or d.dims:
                continue
            if d.entity is None:
                row[d.name] = rt.S[d.name]
            elif d.kind == "account":
                row[d.name + ".total"] = self._total(d)
            elif d.kind == "flow":
                row[d.name + ".total"] = self.flow_totals[d.name]
        if self.model.legislature is not None:
            row["bills_defeated"] = self.defeated
        return row

    def column(self, name: str) -> list:
        return list(self.rt.C[name])

    def evaluate(self, src: str, entity: str | None = None, type: str = "real", unit: str = "1"):
        """Evaluate a one-off formula against the current state: one value, or one per record.

        `type` is "int", "real" or "bool". Nothing is stored and no range is checked, so a
        real result may be an infinity or not-a-number. Random draws use the index of the
        step that would run next.
        """
        fn, _, _ = compile_formula(src, self.model, self.rt, entity, type, parse_unit(unit), "evaluate")
        self.rt.generation += 1
        if entity is None:
            return fn(0)
        return [fn(i) for i in range(len(self.model.entities[entity].ids))]

    def state_hash(self) -> str:
        """SHA-256 over everything needed to continue the run, in a fixed encoding.

        Header, then for each lever, account, state and prev()-read var or flow, in
        ascending name order: the UTF-8 name, a zero byte, then its value(s) in record
        order. Whole numbers are 8-byte little-endian two's complement, reals are the
        8-byte little-endian IEEE 754 pattern, booleans are one byte.
        """
        sym, rt = self.model.symbols, self.rt
        digest = hashlib.sha256(b"PSIM-STATE-v0\0" + struct.pack("<Q", self.steps_done))
        packers = {"int": struct.Struct("<q").pack, "real": struct.Struct("<d").pack,
                   "bool": lambda v: b"\x01" if v else b"\x00"}
        names = sorted(n for n, d in sym.items()
                       if d.kind in ("lever", "account", "state") or n in self.lagged)
        for name in names:
            d = sym[name]
            pack = packers[d.type]
            digest.update(name.encode("utf-8") + b"\0")
            if d.entity is None and not d.dims:
                digest.update(pack(rt.S[name]))
            else:
                digest.update(b"".join(pack(v) for v in rt.C[name]))
        return digest.hexdigest()


def from_scenario(scenario: Scenario) -> Simulation:
    return Simulation(scenario.model, scenario.seed, scenario.preset, scenario.params,
                      scenario.levers, scenario.commands)
