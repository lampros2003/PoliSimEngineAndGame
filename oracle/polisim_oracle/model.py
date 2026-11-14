"""Model-file format v0: loading and structural validation.

Executable definition of docs/spec/01-model-format-v0.md. Formulas are compiled later,
by the simulation, because compiling them needs the run-time store.
"""

from __future__ import annotations

import csv
import hashlib
import re
import tomllib
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from . import units as U
from .expr import FUNCTIONS, I64_MAX, I64_MIN
from .rng import fnv1a32


class ModelError(Exception):
    """The model files are inconsistent. Raised at load time."""


_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
_WHOLE = re.compile(r"[+-]?\d+\Z")
_RESERVED = set(FUNCTIONS) | {"and", "or", "not", "true", "false"}
_TYPES = {"money": ("int", True), "int": ("int", False), "real": ("real", False), "bool": ("bool", False)}
_SECTIONS = ("model", "sector", "instrument", "entity", "stream", "table",
             "param", "lever", "var", "state", "flow", "account")


@dataclass
class Decl:
    """Anything a formula can name."""
    name: str
    kind: str  # param | lever | column | var | flow | state | account
    type: str  # int | real | bool
    unit: U.Unit
    money: bool = False  # file values are in major currency units and scaled on load
    entity: str | None = None  # None: one value for the nation; else one value per record
    phase: int | None = None  # var/flow: evaluation phase; state: phase of its update
    expr: str | None = None  # var/flow formula, or a state's `next` formula
    initial: object = None  # raw value, or {"column": name}
    range: tuple[float, float] | None = None
    spec: dict = field(default_factory=dict)


@dataclass
class Entity:
    name: str
    ids: list[int]
    weights: list[int]
    raw: dict[str, list[str]]  # every CSV column as text


@dataclass
class Table:
    name: str
    unit: U.Unit
    bands: list[tuple[str, str]]  # (lower threshold formula, rate formula), ascending


@dataclass
class Flow:
    name: str
    src: str  # paying sector
    dst: str  # receiving sector
    instrument: str


@dataclass
class Model:
    root: Path
    id: str
    currency: str
    minor: int  # minor units per major unit (100 pence per pound)
    step_unit: U.Unit
    phases: list[str]
    sectors: dict[str, str | None]  # sector -> entity that holds its accounts, or None
    instruments: dict[str, dict]  # instrument -> {"unit": Unit, "issuer": sector}
    entities: dict[str, Entity]
    streams: dict[str, int]
    tables: dict[str, Table]
    symbols: dict[str, Decl]  # declaration order is file order
    flows: dict[str, Flow]
    accounts: dict[tuple[str, str], str]  # (sector, instrument) -> account name
    model_hash: str


def convert(raw, typ: str, money: bool, minor: int, what: str):
    """Turn a TOML or CSV value into a run-time value of the declared type."""
    if typ == "bool":
        if isinstance(raw, bool):
            return raw
        if isinstance(raw, str) and raw.strip().lower() in ("1", "true"):
            return True
        if isinstance(raw, str) and raw.strip().lower() in ("0", "false"):
            return False
        raise ModelError(f"{what}: expected true or false, got {raw!r}")
    if isinstance(raw, bool):
        raise ModelError(f"{what}: expected a number, got {raw!r}")
    if isinstance(raw, str):
        text = raw.strip()
        try:
            raw = int(text) if _WHOLE.match(text) else float(text)
        except ValueError:
            raise ModelError(f"{what}: {text!r} is not a number") from None
    if not isinstance(raw, (int, float)):
        raise ModelError(f"{what}: expected a number, got {raw!r}")
    if typ == "real":
        return float(raw)
    if money:
        if isinstance(raw, int):
            value = raw * minor
        else:
            scaled = raw * minor
            if scaled != scaled or abs(scaled) > 9.0e18:
                raise ModelError(f"{what}: {raw!r} is out of range")
            # Read the number as the shortest decimal that gives this float, which is what
            # was typed, and scale that exactly: 2301745961.03 is 230174596103 pence, though
            # 2301745961.03 * 100 in floating point is 230174596102.99997.
            exact = Decimal(repr(raw)) * minor
            if exact != exact.to_integral_value():
                raise ModelError(f"{what}: {raw!r} has more decimal places than the currency")
            value = int(exact)
    else:
        if not isinstance(raw, int):
            raise ModelError(f"{what}: expected a whole number, got {raw!r}")
        value = raw
    if value < I64_MIN or value > I64_MAX:
        raise ModelError(f"{what}: {raw!r} does not fit in 64 bits")
    return value


def _unit(spec: dict, what: str, default: str | None = None) -> U.Unit:
    text = spec.get("unit", default)
    if text is None:
        raise ModelError(f"{what}: missing 'unit'")
    try:
        return U.parse_unit(text)
    except U.UnitError as exc:
        raise ModelError(f"{what}: {exc}") from None


def _type(spec: dict, what: str) -> tuple[str, bool]:
    name = spec.get("type")
    if name not in _TYPES:
        raise ModelError(f"{what}: 'type' must be one of {', '.join(_TYPES)}")
    return _TYPES[name]


def _range(spec: dict, money: bool, minor: int, what: str):
    if "range" not in spec:
        return None
    try:
        lo, hi = (float(x) for x in spec["range"])
    except (TypeError, ValueError):
        raise ModelError(f"{what}: 'range' must be [low, high]") from None
    scale = float(minor) if money else 1.0
    return (lo * scale, hi * scale)


def _read_entity(root: Path, name: str, spec: dict) -> Entity:
    path = root / spec["data"]
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ModelError(f"entity {name}: {path} has no rows")
    raw = {column: [row[column] for row in rows] for column in rows[0]}
    for needed in (spec["id"], spec["weight"]):
        if needed not in raw:
            raise ModelError(f"entity {name}: column {needed!r} not found in {path.name}")
    ids = [convert(v, "int", False, 1, f"entity {name} id") for v in raw[spec["id"]]]
    weights = [convert(v, "int", False, 1, f"entity {name} weight") for v in raw[spec["weight"]]]
    if len(set(ids)) != len(ids) or min(ids) < 0:
        raise ModelError(f"entity {name}: ids must be unique and non-negative")
    if min(weights) <= 0:
        raise ModelError(f"entity {name}: weights must be positive whole numbers")
    return Entity(name, ids, weights, raw)


def load_model(path: str | Path) -> Model:
    path = Path(path)
    manifest = path / "model.toml" if path.is_dir() else path
    root = manifest.parent

    # ---- read and merge files; hash the bytes that define the model
    digest = hashlib.sha256()
    merged: dict[str, dict] = {section: {} for section in _SECTIONS}

    def read(file: Path) -> dict:
        data = file.read_bytes()
        digest.update(file.relative_to(root).as_posix().encode() + b"\0" + data + b"\0")
        return tomllib.loads(data.decode("utf-8"))

    first = read(manifest)
    documents = [first] + [read(root / f) for f in first.get("model", {}).get("files", [])]
    for doc in documents:
        for section, content in doc.items():
            if section not in merged:
                raise ModelError(f"unknown section [{section}]")
            if section == "model":
                merged["model"].update(content)
                continue
            for name, spec in content.items():
                if name in merged[section]:
                    raise ModelError(f"{section}.{name} is declared twice")
                merged[section][name] = spec

    head = merged["model"]
    if head.get("format") != 0:
        raise ModelError("this loader reads model format 0 only")
    minor = head["minor_units"]
    phases = list(head["phases"])
    step_unit = U.parse_unit(head["step"])

    sectors = {name: spec.get("entity") for name, spec in merged["sector"].items()}
    instruments = {}
    for name, spec in merged["instrument"].items():
        if spec.get("issuer") not in sectors:
            raise ModelError(f"instrument {name}: issuer must be a declared sector")
        instruments[name] = {"unit": _unit(spec, f"instrument {name}"), "issuer": spec["issuer"]}

    entities = {name: _read_entity(root, name, spec) for name, spec in merged["entity"].items()}
    for name, spec in merged["entity"].items():
        data_file = root / spec["data"]
        digest.update(data_file.relative_to(root).as_posix().encode() + b"\0" + data_file.read_bytes() + b"\0")
    for sector, entity in sectors.items():
        if entity is not None and entity not in entities:
            raise ModelError(f"sector {sector}: unknown entity {entity!r}")

    streams: dict[str, int] = {}
    for name in merged["stream"]:
        stream_id = fnv1a32(name)
        if stream_id in streams.values():
            raise ModelError(f"stream {name}: id collides with another stream; rename one")
        streams[name] = stream_id

    tables = {}
    for name, spec in merged["table"].items():
        if spec.get("kind") != "marginal":
            raise ModelError(f"table {name}: only kind = \"marginal\" exists in format 0")
        bands = [(str(band["from"]), str(band["rate"])) for band in spec["bands"]]
        if not bands:
            raise ModelError(f"table {name}: needs at least one band")
        tables[name] = Table(name, _unit(spec, f"table {name}"), bands)

    # ---- declarations
    symbols: dict[str, Decl] = {}

    def declare(decl: Decl) -> None:
        if not _NAME.match(decl.name) or decl.name in _RESERVED:
            raise ModelError(f"{decl.kind} {decl.name!r}: not a usable name")
        if decl.name in symbols or decl.name in tables or decl.name in streams or decl.name in entities:
            raise ModelError(f"the name {decl.name!r} is used twice")
        symbols[decl.name] = decl

    def phase_of(spec: dict, what: str) -> int:
        if spec.get("phase") not in phases:
            raise ModelError(f"{what}: 'phase' must be one of {phases}")
        return phases.index(spec["phase"])

    def entity_of(spec: dict, what: str) -> str | None:
        entity = spec.get("entity")
        if entity is not None and entity not in entities:
            raise ModelError(f"{what}: unknown entity {entity!r}")
        return entity

    for ent_name, ent_spec in merged["entity"].items():
        for name, spec in ent_spec.get("columns", {}).items():
            what = f"column {name}"
            typ, money = _type(spec, what)
            if name not in entities[ent_name].raw:
                raise ModelError(f"{what}: not found in the data of entity {ent_name}")
            declare(Decl(name, "column", typ, _unit(spec, what, "1" if typ == "bool" else None),
                         money, ent_name, spec=spec))

    for name, spec in merged["param"].items():
        what = f"param {name}"
        typ, money = _type(spec, what)
        declare(Decl(name, "param", typ, _unit(spec, what, "1" if typ == "bool" else None),
                     money, range=_range(spec, money, minor, what), spec=spec))

    for name, spec in merged["lever"].items():
        what = f"lever {name}"
        typ, money = _type(spec, what)
        if "default" not in spec:
            raise ModelError(f"{what}: missing 'default'")
        declare(Decl(name, "lever", typ, _unit(spec, what, "1" if typ == "bool" else None),
                     money, initial=spec["default"], range=_range(spec, money, minor, what), spec=spec))

    for name, spec in merged["var"].items():
        what = f"var {name}"
        typ, money = _type(spec, what)
        if "expr" not in spec:
            raise ModelError(f"{what}: missing 'expr'")
        declare(Decl(name, "var", typ, _unit(spec, what, "1" if typ == "bool" else None), money,
                     entity_of(spec, what), phase_of(spec, what), spec["expr"], spec.get("initial"),
                     _range(spec, money, minor, what), spec))

    for name, spec in merged["state"].items():
        what = f"state {name}"
        typ, money = _type(spec, what)
        if "next" not in spec or "initial" not in spec:
            raise ModelError(f"{what}: needs both 'initial' and 'next'")
        declare(Decl(name, "state", typ, _unit(spec, what, "1" if typ == "bool" else None), money,
                     entity_of(spec, what), phase_of(spec, what), spec["next"], spec["initial"],
                     _range(spec, money, minor, what), spec))

    accounts: dict[tuple[str, str], str] = {}
    for name, spec in merged["account"].items():
        what = f"account {name}"
        sector, instrument = spec.get("sector"), spec.get("instrument")
        if sector not in sectors or instrument not in instruments:
            raise ModelError(f"{what}: needs a declared 'sector' and 'instrument'")
        if (sector, instrument) in accounts:
            raise ModelError(f"{what}: sector {sector} already has an account in {instrument}")
        issuer = instruments[instrument]["issuer"] == sector
        if issuer == ("initial" in spec):
            raise ModelError(f"{what}: holders need 'initial'; the issuer's balance is derived")
        entity = sectors[sector]
        unit = instruments[instrument]["unit"]
        if entity is not None:
            unit = U.div(unit, ((entity, 1),))
        accounts[(sector, instrument)] = name
        declare(Decl(name, "account", "int", unit, True, entity, initial=spec.get("initial"),
                     range=_range(spec, True, minor, what), spec=spec))

    flows: dict[str, Flow] = {}
    for name, spec in merged["flow"].items():
        what = f"flow {name}"
        src, dst = spec.get("from"), spec.get("to")
        instrument = spec.get("instrument", next(iter(instruments), None))
        if src not in sectors or dst not in sectors or src == dst:
            raise ModelError(f"{what}: 'from' and 'to' must be two different declared sectors")
        if instrument not in instruments:
            raise ModelError(f"{what}: unknown instrument {instrument!r}")
        for sector in (src, dst):
            if (sector, instrument) not in accounts:
                raise ModelError(f"{what}: sector {sector} has no account in {instrument}")
        held = [sectors[s] for s in (src, dst) if sectors[s] is not None]
        if len(held) == 2:
            raise ModelError(f"{what}: flows between two per-record sectors are not in format 0")
        entity = held[0] if held else None
        unit = U.div(instruments[instrument]["unit"], step_unit)
        if entity is not None:
            unit = U.div(unit, ((entity, 1),))
        if "unit" in spec and _unit(spec, what) != unit:
            raise ModelError(f"{what}: unit must be {U.fmt(unit)}")
        if "expr" not in spec:
            raise ModelError(f"{what}: missing 'expr'")
        flows[name] = Flow(name, src, dst, instrument)
        declare(Decl(name, "flow", "int", unit, True, entity, phase_of(spec, what), spec["expr"],
                     spec.get("initial"), _range(spec, True, minor, what), spec))

    for instrument, info in instruments.items():
        if (info["issuer"], instrument) not in accounts:
            raise ModelError(f"instrument {instrument}: the issuer {info['issuer']} needs an account")
        if sectors[info["issuer"]] is not None:
            raise ModelError(f"instrument {instrument}: the issuer cannot be a per-record sector")

    return Model(root, head["id"], head["currency"], minor, step_unit, phases, sectors, instruments,
                 entities, streams, tables, symbols, flows, accounts, digest.hexdigest())


@dataclass
class Scenario:
    name: str
    model: Model
    seed: int
    steps: int
    preset: str
    params: dict
    levers: dict
    commands: dict[int, dict]  # step -> {lever: raw value}, applied before that step runs


def load_scenario(path: str | Path) -> Scenario:
    path = Path(path)
    doc = tomllib.loads(path.read_text(encoding="utf-8"))
    head = doc["scenario"]
    commands: dict[int, dict] = {}
    for command in doc.get("command", []):
        commands.setdefault(int(command["step"]), {}).update(command["set"])
    return Scenario(path.stem, load_model((path.parent / head["model"]).resolve()), int(head["seed"]),
                    int(head["steps"]), head.get("preset", "central"), doc.get("params", {}),
                    doc.get("levers", {}), commands)
