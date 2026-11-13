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
from .units import parse_unit


class Runtime:
    """Values the compiled formulas read. The dict objects are never replaced."""

    def __init__(self, seed: int):
        self.S: dict[str, object] = {}  # current scalars
        self.C: dict[str, list] = {}  # current per-record columns
        self.PS: dict[str, object] = {}  # scalars at the end of the previous step
        self.PC: dict[str, list] = {}  # columns at the end of the previous step
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
        m, minor = model, model.minor
        sym = m.symbols

        # ---- parameters, levers, data columns
        overrides = dict(params or {})
        for d in sym.values():
            if d.kind == "param":
                if d.name in overrides:
                    raw = overrides.pop(d.name)
                elif "value" in d.spec:
                    raw = d.spec["value"]
                elif preset in d.spec:
                    raw = d.spec[preset]
                else:
                    raise ModelError(f"param {d.name}: no 'value' and no {preset!r} preset")
                rt.S[d.name] = self._checked(d, convert(raw, d.type, d.money, minor, f"param {d.name}"))
            elif d.kind == "column":
                texts = m.entities[d.entity].raw[d.name]
                rt.C[d.name] = [convert(t, d.type, d.money, minor, f"column {d.name}") for t in texts]
        if overrides:
            raise ModelError(f"unknown parameter(s): {', '.join(overrides)}")
        lever_overrides = dict(levers or {})
        for d in sym.values():
            if d.kind == "lever":
                self._set_lever(d.name, lever_overrides.pop(d.name, d.initial))
        if lever_overrides:
            raise ModelError(f"unknown lever(s): {', '.join(lever_overrides)}")

        # ---- initial state: states and holders' accounts, then issuers' accounts
        def initial(d):
            what = f"{d.kind} {d.name} initial"
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
        for instrument, info in m.instruments.items():
            held = sum(self._total(sym[name]) for (sector, ins), name in m.accounts.items()
                       if ins == instrument and sector != info["issuer"])
            issuer = m.accounts[(info["issuer"], instrument)]
            self._store(sym[issuer], self._int64(-held, f"account {issuer}"))

        # ---- compile formulas and build the evaluation plan
        self.fn: dict[str, object] = {}
        deps: dict[str, set[str]] = {}
        self.lagged: set[str] = set()
        for d in sym.values():
            if d.expr is None:
                continue
            label = f"{d.kind} {d.name}" + (" (next)" if d.kind == "state" else "")
            self.fn[d.name], deps[d.name], lagged = compile_formula(
                d.expr, m, rt, d.entity, d.type, d.unit, label)
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
        (self.rt.S if d.entity is None else self.rt.C)[d.name] = self._checked(d, value)

    def _total(self, d) -> int:
        """Sector-level total of a scalar or per-record whole-number quantity."""
        if d.entity is None:
            return self.rt.S[d.name]
        weights = self.model.entities[d.entity].weights
        return sum(w * v for w, v in zip(weights, self.rt.C[d.name]))

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
        fn = self.fn[d.name]
        if d.entity is None:
            return fn(0)
        return [fn(i) for i in range(len(self.model.entities[d.entity].ids))]

    # ------------------------------------------------------------------ the step

    def step(self) -> dict:
        m, rt, sym = self.model, self.rt, self.model.symbols
        try:
            for name, raw in self.commands.get(rt.step, {}).items():
                self._set_lever(name, raw)

            for order, states in self.plan:
                for name in order:
                    self._store(sym[name], self._evaluate(sym[name]))
                pending = [(sym[name], self._evaluate(sym[name])) for name in states]
                for d, value in pending:
                    self._store(d, value)

            self._post_flows()
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
                total = sum(w * a for w, a in zip(m.entities[d.entity].weights, amounts))
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
            if d.kind == "param":
                continue
            if d.entity is None:
                row[d.name] = rt.S[d.name]
            elif d.kind == "account":
                row[d.name + ".total"] = self._total(d)
            elif d.kind == "flow":
                row[d.name + ".total"] = self.flow_totals[d.name]
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
            if d.entity is None:
                digest.update(pack(rt.S[name]))
            else:
                digest.update(b"".join(pack(v) for v in rt.C[name]))
        return digest.hexdigest()


def from_scenario(scenario: Scenario) -> Simulation:
    return Simulation(scenario.model, scenario.seed, scenario.preset, scenario.params,
                      scenario.levers, scenario.commands)
