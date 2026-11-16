"""Drive the engine from Python through `polisim serve` (docs/spec/09-serve.md).

The tests in tests/ and the UK tools (tools/uk/hindcast.py, calibrate.py, screen.py) use
this module. Standard library only. The engine must be built first:

    cargo build --release

    from engine import Simulation, load_model
    model = load_model("models/uk")
    sim = Simulation(model, seed=2025, levers={"basic_rate": 0.21})
    rows = sim.run(12)            # one dict per month: step, hash and every national value
    sim.column("net_income")      # one value per record or cell
    sim.evaluate("wsum(household, net_income)", unit="GBP/month")

A model is one `polisim serve` process, which loads the model once; each simulation is a
run in it.
"""

from __future__ import annotations

import atexit
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "target" / "release" / ("polisim.exe" if sys.platform == "win32" else "polisim")


class EngineError(Exception):
    """An error the engine reported."""

    reply: dict = {}


class ModelError(EngineError):
    """The model files are inconsistent (raised while loading or starting a run)."""


class FormulaError(EngineError):
    """A formula is malformed: syntax, type or unit."""


class SimError(EngineError):
    """A run could not continue: a formula or posting produced an illegal value."""


class RequestError(EngineError):
    """The request itself was wrong (an unknown name or request)."""


KINDS = {"model": ModelError, "formula": FormulaError, "run": SimError, "request": RequestError}


def toml(value) -> str:
    """A Python value as a TOML value on one line."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return "nan" if math.isnan(value) else repr(value)  # repr: the shortest exact form; inf is TOML too
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)  # a JSON string is a TOML basic string
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(toml(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(f"{json.dumps(str(k))} = {toml(v)}" for k, v in value.items()) + "}"
    raise TypeError(f"cannot pass {value!r} to the engine")


class Server:
    """One `polisim serve` process."""

    def __init__(self, path: Path, mods=()):
        if not EXE.exists():
            raise SystemExit(f"the engine is not built: {EXE} is missing; run `cargo build --release` first")
        args = [str(EXE), "serve", str(path)]
        for m in mods:
            args += ["--mod", str(m)]
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
        self.closing: list[int] = []  # runs to close before the next request
        _RUNNING.add(self)
        try:
            self.hello = self._read()
        except BaseException:
            self.close()
            raise

    def _read(self) -> dict:
        line = self.process.stdout.readline()
        if not line:
            raise EngineError(f"polisim serve stopped (exit code {self.process.wait()})")
        reply = json.loads(line)
        if "error" in reply:
            error = KINDS.get(reply["kind"], EngineError)(reply["error"])
            error.reply = reply
            raise error
        return reply

    def ask(self, line: str) -> dict:
        # Runs given up by simulations that were garbage collected are closed here, never
        # from the collector itself, which may run between a request and its reply.
        while self.closing:
            self.process.stdin.write(f"@{self.closing.pop()} close\n".encode())
            try:
                self._read()
            except RequestError:
                pass
        self.process.stdin.write(line.encode("utf-8") + b"\n")
        return self._read()

    def close(self) -> None:
        _RUNNING.discard(self)
        try:
            self.process.stdin.close()  # the process ends at the end of its input
        except OSError:
            pass
        self.process.wait()
        self.process.stdout.close()


# Every process not yet closed; what is left is closed at exit.
_RUNNING: set[Server] = set()
atexit.register(lambda: [server.close() for server in list(_RUNNING)])


class Symbol:
    """A symbol as the engine describes it: name, kind, type ("int", "real" or "bool"),
    money, unit, entity, phase, dims, range, initial and spec (as written in the model)."""

    def __init__(self, info: dict):
        self.__dict__.update(info)


class Dim:
    def __init__(self, info: dict):
        self.name, self.first, self.members, self.labels = info["name"], info["first"], info["members"], info["labels"]


class Entity:
    def __init__(self, info: dict):
        self.name, self.ids, self.weights = info["name"], info["ids"], info["weights"]


class ModInfo:
    def __init__(self, info: dict):
        self.__dict__.update(info)


class Model:
    """A loaded model (a model folder, or a scenario file and its model): one served process."""

    def __init__(self, path, mods=()):
        self.path = Path(path)
        self.server = Server(self.path, mods)
        self.model_hash = self.server.hello["model_hash"]
        self._info: dict | None = None
        self._symbols: dict[str, Symbol] | None = None

    @property
    def info(self) -> dict:
        if self._info is None:
            self._info = self.server.ask("model")
        return self._info

    @property
    def symbols(self) -> dict[str, Symbol]:
        if self._symbols is None:
            self._symbols = {s["name"]: Symbol(s) for s in self.server.ask("symbols")["symbols"]}
        return self._symbols

    @property
    def dims(self) -> dict[str, Dim]:
        return {d["name"]: Dim(d) for d in self.info["dims"]}

    @property
    def entities(self) -> dict[str, Entity]:
        return {e["name"]: Entity(e) for e in self.info["entities"]}

    @property
    def accounts(self) -> dict[tuple[str, str], str]:
        """(sector, instrument) -> account."""
        return {(a["sector"], a["instrument"]): a["name"] for a in self.info["accounts"]}

    @property
    def dilemmas(self) -> list[dict]:
        return self.info["dilemmas"]

    @property
    def mods(self) -> list[ModInfo]:
        return [ModInfo(m) for m in self.info["mods"]]

    @property
    def mod_notes(self) -> list[str]:
        return self.info["mod_notes"]

    def __del__(self):
        try:
            self.server.close()
        except Exception:
            pass


def load_model(path, mods=()) -> Model:
    """Loads a model folder (with mods, in order); ModelError or FormulaError if it is refused."""
    return Model(path, mods)


class Scenario:
    """A scenario file: its model and settings."""

    def __init__(self, path):
        self.path = Path(path)
        self.model = Model(self.path)
        s = self.model.server.ask("scenario")
        self.name, self.seed, self.steps, self.preset = s["name"], s["seed"], s["steps"], s["preset"]
        self.params, self.levers = s["params"], s["levers"]
        self.commands: dict[int, dict] = {}
        for step, name, value in s["commands"]:
            self.commands.setdefault(step, {})[name] = value


def load_scenario(path) -> Scenario:
    return Scenario(path)


class _Values:
    """`sim.rt.S[name]` and `sim.rt.C[name]`: a value now, by name."""

    def __init__(self, sim):
        self.sim = sim

    def __getitem__(self, name):
        return self.sim._get(name)


class _Runtime:
    def __init__(self, sim):
        self.S = self.C = _Values(sim)


class Simulation:
    """One run. `commands` maps a step to the lever changes (and dilemma answers) made at its
    start; it may be changed between steps."""

    def __init__(self, model: Model, seed: int = 0, preset: str = "central", params: dict | None = None,
                 levers: dict | None = None, commands: dict[int, dict] | None = None):
        self.model = model
        self.commands = dict(commands or {})
        self.steps_done = 0
        # Any whole number, reduced to 64 bits (sent as the signed number with the same bits).
        settings = {"seed": (seed + (1 << 63)) % (1 << 64) - (1 << 63), "preset": preset,
                    "params": dict(params or {}), "levers": dict(levers or {})}
        self._run = model.server.ask("open " + toml(settings))["run"]

    @property
    def rt(self) -> _Runtime:
        return _Runtime(self)  # made on each use, so a simulation holds no cycle

    def _ask(self, request: str) -> dict:
        return self.model.server.ask(f"@{self._run} {request}")

    def _get(self, name: str):
        return self._ask(f"get {name}")["value"]

    def step(self) -> dict:
        return self.run(1)[0]

    def run(self, steps: int) -> list[dict]:
        rows: list[dict] = []
        while len(rows) < steps:
            for name, value in self.commands.get(self.steps_done, {}).items():
                self._ask(f"set {name} {toml(value)}")
            # The steps up to the next one with commands go in one request.
            ahead = 1
            while len(rows) + ahead < steps and not self.commands.get(self.steps_done + ahead):
                ahead += 1
            try:
                got = self._ask(f"step {ahead}")["rows"]
            except SimError as error:
                self.steps_done += len(error.reply.get("rows", []))
                raise
            rows += got
            self.steps_done += len(got)
        return rows

    def column(self, name: str) -> list:
        return list(self._get(name))

    def evaluate(self, src: str, entity: str | None = None, type: str = "real", unit: str = "1"):
        request = {"formula": src, "type": type, "unit": unit}
        if entity is not None:
            request["entity"] = entity
        return self._ask("evaluate " + toml(request))["value"]

    @property
    def votes(self) -> list[dict]:
        return self._ask("votes")["votes"]

    def __del__(self):
        run = getattr(self, "_run", None)
        if run is not None:
            self.model.server.closing.append(run)


def from_scenario(scenario: Scenario) -> Simulation:
    return Simulation(scenario.model, scenario.seed, scenario.preset, scenario.params, scenario.levers,
                      scenario.commands)


if __name__ == "__main__":  # a quick look: python tools/engine.py [scenario.toml]
    s = load_scenario(sys.argv[1] if len(sys.argv) > 1 else ROOT / "models" / "toy" / "scenarios" / "baseline.toml")
    print(s.name, s.model.model_hash, from_scenario(s).run(3)[-1]["hash"])
