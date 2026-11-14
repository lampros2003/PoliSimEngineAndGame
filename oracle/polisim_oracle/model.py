"""Model-file format v0: loading and structural validation.

Executable definition of docs/spec/01-model-format-v0.md. Formulas are compiled later,
by the simulation, because compiling them needs the run-time store.
"""

from __future__ import annotations

import csv
import hashlib
import itertools
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
_SECTIONS = ("model", "legislature", "dim", "sector", "instrument", "entity", "stream", "table",
             "param", "lever", "var", "state", "flow", "account", "renamed")
MAX_CELLS = 16_777_216


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
    dims: tuple[str, ...] = ()  # format 1: one value per cell of these dimensions
    data: dict[str, list[str]] = field(default_factory=dict)  # format 1: CSV column -> text per cell
    rake: Rake | None = None  # format 1 (S4.4): a weight state's rake, instead of `next`


@dataclass
class Slot:
    count: str  # record formula
    at: list[str]  # record formulas, one per dimension of the target


@dataclass
class Margin:
    target: str  # national param, var or state with dimensions
    slots: list[Slot]


@dataclass
class Rake:
    """Format 1 (S4.4): iterative proportional updating of a weight state."""
    when: str  # national bool formula
    passes: int
    margins: list[Margin]


@dataclass
class Dim:
    """Format 1: a named, ordered set of members."""
    name: str
    kind: str  # "range" | "list"
    members: list  # whole numbers for a range, names for a list
    labels: list[str]
    first: int = 0  # a range's first member

    @property
    def size(self) -> int:
        return len(self.members)

    @property
    def position(self) -> dict:
        return {m: i for i, m in enumerate(self.members)}


@dataclass
class Entity:
    name: str
    ids: list[int]
    weights: list[int]  # from the data; a run's current weights are in its runtime
    raw: dict[str, list[str]]  # every CSV column as text
    weight_state: str | None = None  # format 1 (S4.4): weights held by this state


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
    dims: dict[str, Dim] = field(default_factory=dict)
    format: int = 0
    legislature: dict[str, str] | None = None  # format 1 (S5.4): seats, governing, position
    mods: list[ModInfo] = field(default_factory=list)  # S7.1: the mods applied, in order
    mod_notes: list[str] = field(default_factory=list)  # S7.1: e.g. an element two mods patch
    renamed: list[tuple[str, str]] = field(default_factory=list)  # S7.0: (old name, name now), sorted

    def cells(self, dims: tuple[str, ...]) -> list[dict[str, int]]:
        """Coordinates ({dimension: position}) of every cell, in row-major order."""
        sizes = [range(self.dims[d].size) for d in dims]
        return [dict(zip(dims, combo)) for combo in itertools.product(*sizes)]


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
    weight = spec["weight"]
    state = None
    if isinstance(weight, dict):
        if set(weight) != {"state"} or not isinstance(weight["state"], str):
            raise ModelError(f"entity {name}: 'weight' is a column name or {{ state = \"<name>\" }}")
        state = weight["state"]
    for needed in (spec["id"],) + (() if state else (weight,)):
        if needed not in raw:
            raise ModelError(f"entity {name}: column {needed!r} not found in {path.name}")
    ids = [convert(v, "int", False, 1, f"entity {name} id") for v in raw[spec["id"]]]
    if state:
        weights = [1] * len(ids)  # the state's initial value replaces these when a run starts
    else:
        weights = [convert(v, "int", False, 1, f"entity {name} weight") for v in raw[weight]]
    if len(set(ids)) != len(ids) or min(ids) < 0:
        raise ModelError(f"entity {name}: ids must be unique and non-negative")
    if min(weights) <= 0:
        raise ModelError(f"entity {name}: weights must be positive whole numbers")
    return Entity(name, ids, weights, raw, state)


@dataclass
class ModInfo:
    """Stage S7.1: a mod, as its mod.toml describes it."""
    id: str
    name: str
    version: str
    description: str
    model: str | None  # the id of the model it is for, if it names one
    dir: Path


_MOD_ID = re.compile(r"[a-z][a-z0-9_]*\Z")
_MOD_SECTIONS = ("dim", "param", "lever", "var", "state", "flow", "account", "renamed")
_PATCH_KINDS = ("param", "lever", "var", "state", "flow", "account")


def read_mod(folder: str | Path) -> tuple[ModInfo, list[str], bytes]:
    """Stage S7.1: a mod folder's mod.toml: its description, its files and the file's bytes."""
    folder = Path(folder)
    file = folder / "mod.toml"
    try:
        data = file.read_bytes()
    except OSError as exc:
        raise ModelError(f"cannot read {file}: {exc}") from None
    try:
        doc = tomllib.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        raise ModelError(f"{file}: {exc}") from None
    head = doc.get("mod")
    if not isinstance(head, dict):
        raise ModelError(f"{file}: needs a [mod] table")
    if len(doc) != 1:
        raise ModelError(f"{file}: only [mod] belongs here; elements go in the mod's files")
    mod_id = head.get("id")
    if not isinstance(mod_id, str) or not _MOD_ID.match(mod_id) or mod_id.endswith("_"):
        raise ModelError(f"{file}: [mod] id must be a name of lower-case letters, digits and underscores")
    files = head.get("files", [])
    if not isinstance(files, list) or not all(isinstance(f, str) for f in files):
        raise ModelError(f"mod {mod_id}: files must be a list of file names")

    def text(key, default):
        value = head.get(key)
        return value if isinstance(value, str) else default
    model = head.get("model")
    info = ModInfo(mod_id, text("name", mod_id), text("version", ""), text("description", ""),
                   model if isinstance(model, str) else None, folder)
    return info, files, data


def _relative_name(path: str) -> str:
    return "/".join(part for part in re.split(r"[/\\]", path) if part not in ("", "."))


def _uses_data(spec) -> bool:
    """Stage S7.1: whether an element's declaration reads a data file of its own."""
    if not isinstance(spec, dict):
        return False
    initial = spec.get("initial")
    return "data" in spec or (isinstance(initial, dict) and "data" in initial)


def _apply_mods(merged: dict[str, dict], mod_dirs, digest) -> tuple[list[ModInfo], list[str]]:
    """Stage S7.1: mods, in order. Each adds elements named after it and patches others."""
    model_id = merged["model"].get("id", "")
    mods: list[ModInfo] = []
    notes: list[str] = []
    patched_by: dict[tuple[str, str], str] = {}
    for folder in mod_dirs:
        info, files, data = read_mod(folder)
        mod_id = info.id
        if any(m.id == mod_id for m in mods):
            raise ModelError(f"mod {mod_id} is listed twice")
        if info.model is not None and info.model != model_id:
            raise ModelError(f"mod {mod_id} is for the model {info.model!r}, not {model_id!r}")
        digest.update(f"mod:{mod_id}/mod.toml".encode() + b"\0" + data + b"\0")
        prefix = mod_id + "_"
        patches = []
        for file in files:
            path = Path(folder) / file
            what = f"mod {mod_id}, {_relative_name(file)}"
            try:
                data = path.read_bytes()
            except OSError as exc:
                raise ModelError(f"cannot read {path}: {exc}") from None
            digest.update(f"mod:{mod_id}/{_relative_name(file)}".encode() + b"\0" + data + b"\0")
            try:
                doc = tomllib.loads(data.decode("utf-8"))
            except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
                raise ModelError(f"{what}: {exc}") from None
            for section, content in doc.items():
                if not isinstance(content, dict):
                    raise ModelError(f"{what}: [{section}] must be a table")
                if section == "patch":
                    for kind, elements in content.items():
                        if kind not in _PATCH_KINDS:
                            raise ModelError(f"{what}: [patch.{kind}] is not a kind of element a mod can patch")
                        if not isinstance(elements, dict):
                            raise ModelError(f"{what}: [patch.{kind}] must be a table")
                        for element, spec in elements.items():
                            if not isinstance(spec, dict):
                                raise ModelError(f"{what}: patch.{kind}.{element} must be a table")
                            patches.append((kind, element, spec))
                    continue
                if section not in _MOD_SECTIONS:
                    raise ModelError(f"{what}: a mod cannot add to [{section}]")
                for name, spec in content.items():
                    if not name.startswith(prefix):
                        raise ModelError(f"{what}: {section}.{name}: a mod's names start with {prefix!r}")
                    if section != "renamed" and _uses_data(spec):
                        raise ModelError(f"{what}: {section}.{name}: mods cannot bring data files yet")
                    if name in merged[section]:
                        raise ModelError(f"{what}: {section}.{name} is declared twice")
                    merged[section][name] = spec
        for kind, element, spec in patches:
            what = f"mod {mod_id}: patch.{kind}.{element}"
            target = merged[kind].get(element)
            if not isinstance(target, dict):
                raise ModelError(f"{what}: the model has no {kind} {element}")
            if _uses_data(spec):
                raise ModelError(f"{what}: mods cannot bring data files yet")
            for key, value in spec.items():
                if isinstance(value, str) and "{base}" in value:
                    old = target.get(key)
                    if not isinstance(old, str):
                        raise ModelError(f"{what}: {key} has no earlier text for {{base}}")
                    value = value.replace("{base}", f"({old})" if key in ("expr", "next") else old)
                target[key] = value
            earlier = patched_by.get((kind, element))
            patched_by[(kind, element)] = mod_id
            if earlier is not None and earlier != mod_id:
                notes.append(f"{kind} {element} is patched by both {earlier} and {mod_id}; {mod_id} comes later")
        mods.append(info)
    return mods, notes


def load_model(path: str | Path, mods: list[str | Path] = ()) -> Model:
    """A model folder (or its model.toml), with mods applied in order (stage S7.1)."""
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
            if section in ("model", "legislature"):
                merged[section].update(content)
                continue
            for name, spec in content.items():
                if name in merged[section]:
                    raise ModelError(f"{section}.{name} is declared twice")
                merged[section][name] = spec
    applied, mod_notes = _apply_mods(merged, mods, digest)

    head = merged["model"]
    fmt = head.get("format")
    if fmt not in (0, 1):
        raise ModelError("this loader reads model formats 0 and 1")
    if fmt == 0 and merged["dim"]:
        raise ModelError("dimensions need format = 1")
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

    dims: dict[str, Dim] = {}
    for name, spec in merged["dim"].items():
        what = f"dim {name}"
        if not _NAME.match(name) or name in _RESERVED:
            raise ModelError(f"{what}: not a usable name")
        if ("range" in spec) == ("members" in spec):
            raise ModelError(f"{what}: give either 'range' or 'members'")
        if "range" in spec:
            lo, hi = spec["range"]
            if not all(isinstance(x, int) and not isinstance(x, bool) for x in (lo, hi)) or lo > hi:
                raise ModelError(f"{what}: 'range' must be [first, last], whole numbers, first <= last")
            members, kind = list(range(lo, hi + 1)), "range"
        else:
            members, kind = list(spec["members"]), "list"
            if not members or not all(isinstance(m, str) and _NAME.match(m) and m not in _RESERVED for m in members):
                raise ModelError(f"{what}: members must be usable names")
            if len(set(members)) != len(members):
                raise ModelError(f"{what}: a member is listed twice")
        if len(members) > 1_000_000:
            raise ModelError(f"{what}: more than 1,000,000 members")
        labels = [str(x) for x in spec.get("labels", members)]
        if len(labels) != len(members):
            raise ModelError(f"{what}: one label per member")
        dims[name] = Dim(name, kind, members, labels, members[0] if kind == "range" else 0)

    # Data files of dimensioned elements: read once each, hashed after the entities' in
    # ascending order of path.
    cell_files: dict[str, list[dict[str, str]]] = {}

    def cell_data(dim_names: tuple[str, ...], file: str, columns: list[str], what: str) -> dict[str, list[str]]:
        if file not in cell_files:
            path_ = root / file
            if not path_.is_file():
                raise ModelError(f"{what}: data file {file} not found")
            with open(path_, newline="", encoding="utf-8") as handle:
                cell_files[file] = list(csv.DictReader(handle))
        rows = cell_files[file]
        header = rows[0].keys() if rows else []
        for column in list(dim_names) + columns:
            if column not in header:
                raise ModelError(f"{what}: {file} has no column {column!r}")
        positions = [dims[d].position for d in dim_names]
        strides, stride = [], 1
        for d in reversed(dim_names):
            strides.append(stride)
            stride *= dims[d].size
        strides.reverse()
        out = {c: [None] * stride for c in columns}
        for row in rows:
            flat = 0
            for d, pos, st in zip(dim_names, positions, strides):
                text = row[d].strip()
                key = int(text) if dims[d].kind == "range" and _WHOLE.match(text) else text
                if key not in pos:
                    raise ModelError(f"{what}: {file}: {text!r} is not a member of {d}")
                flat += pos[key] * st
            if out[columns[0]][flat] is not None:
                raise ModelError(f"{what}: {file}: a cell appears twice")
            for c in columns:
                out[c][flat] = row[c]
        if any(v is None for v in out[columns[0]]):
            raise ModelError(f"{what}: {file}: some cells are missing")
        return out

    def dims_of(spec: dict, kind: str, what: str) -> tuple[str, ...]:
        if "dims" not in spec:
            return ()
        if fmt != 1:
            raise ModelError(f"{what}: dimensions need format = 1")
        if kind not in ("param", "var", "state"):
            raise ModelError(f"{what}: a {kind} cannot have dimensions in format 1")
        if spec.get("entity") is not None:
            raise ModelError(f"{what}: an element cannot have both an entity and dimensions")
        names = tuple(spec["dims"])
        if not names or len(set(names)) != len(names) or not all(n in dims for n in names):
            raise ModelError(f"{what}: 'dims' must list declared dimensions, each once")
        cells = 1
        for n in names:
            cells *= dims[n].size
        if cells > MAX_CELLS:
            raise ModelError(f"{what}: more than {MAX_CELLS:,} cells")
        return names

    def with_data(decl: Decl, value) -> Decl:
        """Reads the CSV behind a dimensioned parameter or initial value."""
        if not decl.dims:
            return decl
        what = f"{decl.kind} {decl.name}"
        if decl.kind == "param" and "data" in decl.spec:
            columns = decl.spec.get("columns")
            wanted = list(columns.values()) if isinstance(columns, dict) else [decl.spec.get("column", "value")]
            decl.data = cell_data(decl.dims, decl.spec["data"], wanted, what)
        elif isinstance(value, dict) and "data" in value:
            decl.data = cell_data(decl.dims, value["data"], [value.get("column", "value")], what)
        return decl

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
        declare(with_data(Decl(name, "param", typ, _unit(spec, what, "1" if typ == "bool" else None),
                               money, range=_range(spec, money, minor, what), spec=spec,
                               dims=dims_of(spec, "param", what)), None))

    for name, spec in merged["lever"].items():
        what = f"lever {name}"
        typ, money = _type(spec, what)
        if "default" not in spec:
            raise ModelError(f"{what}: missing 'default'")
        dims_of(spec, "lever", what)
        declare(Decl(name, "lever", typ, _unit(spec, what, "1" if typ == "bool" else None),
                     money, initial=spec["default"], range=_range(spec, money, minor, what), spec=spec))

    for name, spec in merged["var"].items():
        what = f"var {name}"
        typ, money = _type(spec, what)
        if "expr" not in spec:
            raise ModelError(f"{what}: missing 'expr'")
        declare(with_data(Decl(name, "var", typ, _unit(spec, what, "1" if typ == "bool" else None), money,
                               entity_of(spec, what), phase_of(spec, what), spec["expr"], spec.get("initial"),
                               _range(spec, money, minor, what), spec, dims_of(spec, "var", what)),
                          spec.get("initial")))

    for name, spec in merged["state"].items():
        what = f"state {name}"
        typ, money = _type(spec, what)
        if "initial" not in spec or ("next" in spec) == ("rake" in spec):
            raise ModelError(f"{what}: needs 'initial' and either 'next' or 'rake'")
        declare(with_data(Decl(name, "state", typ, _unit(spec, what, "1" if typ == "bool" else None), money,
                               entity_of(spec, what), phase_of(spec, what), spec.get("next"), spec["initial"],
                               _range(spec, money, minor, what), spec, dims_of(spec, "state", what),
                               rake=_rake(spec["rake"], what) if "rake" in spec else None),
                          spec["initial"]))

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
        dims_of(spec, "account", what)
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
        dims_of(spec, "flow", what)
        flows[name] = Flow(name, src, dst, instrument)
        declare(Decl(name, "flow", "int", unit, True, entity, phase_of(spec, what), spec["expr"],
                     spec.get("initial"), _range(spec, True, minor, what), spec))

    for instrument, info in instruments.items():
        if (info["issuer"], instrument) not in accounts:
            raise ModelError(f"instrument {instrument}: the issuer {info['issuer']} needs an account")
        if sectors[info["issuer"]] is not None:
            raise ModelError(f"instrument {instrument}: the issuer cannot be a per-record sector")

    _check_weights(entities, sectors, symbols, phases)
    legislature = _check_legislature(merged["legislature"], symbols, fmt)
    renamed = _check_renamed(merged["renamed"], symbols, dims)

    for dim in dims.values():
        if dim.kind == "list":
            for member in dim.members:
                if member in symbols:
                    raise ModelError(f"dim {dim.name}: the member {member!r} has the name of an element")
    for name in dims:
        if name in symbols:
            raise ModelError(f"the name {name!r} is used twice")
    for file in sorted(cell_files, key=lambda f: f.encode("utf-8")):
        digest.update(Path(file).as_posix().encode() + b"\0" + (root / file).read_bytes() + b"\0")

    return Model(root, head["id"], head["currency"], minor, step_unit, phases, sectors, instruments,
                 entities, streams, tables, symbols, flows, accounts, digest.hexdigest(), dims, fmt, legislature,
                 renamed=renamed, mods=applied, mod_notes=mod_notes)


def _rake(spec, what: str) -> Rake:
    """Format 1 (S4.4): the structure of a rake; names and formulas are checked later."""
    what = f"{what} rake"
    if not isinstance(spec, dict) or set(spec) - {"when", "passes", "margin"}:
        raise ModelError(f"{what}: takes 'when', 'passes' and 'margin'")
    passes = spec.get("passes")
    if not isinstance(passes, int) or isinstance(passes, bool) or not 1 <= passes <= 1000:
        raise ModelError(f"{what}: 'passes' must be a whole number from 1 to 1,000")
    if not isinstance(spec.get("when"), str):
        raise ModelError(f"{what}: 'when' must be a formula")
    margins = []
    if not isinstance(spec.get("margin"), list) or not spec["margin"]:
        raise ModelError(f"{what}: needs at least one margin")
    for k, margin in enumerate(spec["margin"]):
        where = f"{what} margin {k + 1}"
        if not isinstance(margin, dict) or set(margin) != {"target", "slots"} or not isinstance(margin["target"], str):
            raise ModelError(f"{where}: needs 'target' and 'slots'")
        slots = margin["slots"]
        if not isinstance(slots, list) or not slots:
            raise ModelError(f"{where}: needs at least one slot")
        parsed = []
        for slot in slots:
            if (not isinstance(slot, dict) or set(slot) != {"count", "at"} or not isinstance(slot["count"], str)
                    or not isinstance(slot["at"], list) or not all(isinstance(a, str) for a in slot["at"])):
                raise ModelError(f"{where}: a slot needs 'count' (a formula) and 'at' (a list of formulas)")
            parsed.append(Slot(slot["count"], list(slot["at"])))
        margins.append(Margin(margin["target"], parsed))
    return Rake(spec["when"], passes, margins)


def _check_renamed(spec: dict, symbols, dims) -> list[tuple[str, str]]:
    """Stage S7.0: `[renamed] old = "new"`. An old name is no longer a name in the model; the
    new one is an element, or itself renamed again (the chain is followed to an element).
    The oracle has no saves; it checks the section as the engine does."""
    for old, new in spec.items():
        if not isinstance(new, str):
            raise ModelError(f"renamed.{old}: must be the element's new name, as text")
        if old in symbols or old in dims:
            raise ModelError(f"renamed.{old}: {old!r} is still a name in the model")
    out = []
    for old, name in spec.items():
        seen = [old]
        while name not in symbols:
            if name not in spec:
                raise ModelError(f"renamed.{old}: {name!r} is not an element of the model")
            if name in seen:
                raise ModelError(f"renamed.{old}: the renames go round in a circle")
            seen.append(name)
            name = spec[name]
        out.append((old, name))
    return sorted(out)


def _check_legislature(spec: dict, symbols, fmt: int) -> dict[str, str] | None:
    """Format 1 (S5.4): the legislature that votes on lever changes, and levers' leanings."""
    for d in symbols.values():
        if d.kind == "lever" and "leaning" in d.spec:
            if d.spec["leaning"] not in ("left", "right"):
                raise ModelError(f"lever {d.name}: 'leaning' is \"left\" or \"right\"")
            if d.type == "bool":
                raise ModelError(f"lever {d.name}: a true/false lever has no leaning")
    if not spec:
        return None
    if fmt != 1:
        raise ModelError("[legislature] needs format = 1")
    if set(spec) != {"seats", "governing", "position"} or not all(isinstance(v, str) for v in spec.values()):
        raise ModelError("[legislature] takes 'seats', 'governing' and 'position', each a name")
    wanted = {"seats": ("state", "int"), "governing": ("state", "bool"), "position": ("param", "real")}
    dims = None
    for key, (kind, typ) in wanted.items():
        d = symbols.get(spec[key])
        if d is None or d.kind != kind or d.type != typ or d.money or len(d.dims) != 1:
            raise ModelError(f"[legislature] {key}: must be a {kind} of type {typ} with one dimension")
        if dims is not None and d.dims != dims:
            raise ModelError("[legislature]: seats, governing and position must have the same dimension")
        dims = d.dims
    return dict(spec)


def _check_weights(entities, sectors, symbols, phases) -> None:
    """Format 1 (S4.4): weight states and rakes."""
    for entity in entities.values():
        if entity.weight_state is None:
            continue
        what = f"entity {entity.name}: the weight state {entity.weight_state!r}"
        d = symbols.get(entity.weight_state)
        if d is None or d.kind != "state" or d.entity != entity.name:
            raise ModelError(f"{what} must be a state of that entity")
        if d.type != "int" or d.money or d.unit != U.ONE or d.dims:
            raise ModelError(f"{what} must be of type int and unit 1")
        for sector, held in sectors.items():
            if held == entity.name:
                raise ModelError(f"sector {sector}: its accounts are held in {entity.name}, whose weights change")
    weight_states = {e.weight_state for e in entities.values()}
    for d in symbols.values():
        if d.rake is None:
            continue
        what = f"state {d.name} rake"
        if d.name not in weight_states:
            raise ModelError(f"{what}: only a weight state can have a rake")
        for k, margin in enumerate(d.rake.margins):
            t = symbols.get(margin.target)
            where = f"{what} margin {k + 1}"
            if t is None or t.kind not in ("param", "var", "state") or not t.dims or t.type == "bool":
                raise ModelError(f"{where}: the target must be a param, var or state with dimensions")
            if t.kind == "var" and t.phase > d.phase:
                raise ModelError(f"{where}: the target {t.name} is computed in a later phase "
                                 f"({phases[t.phase]}) than the rake ({phases[d.phase]})")
            for slot in margin.slots:
                if len(slot.at) != len(t.dims):
                    raise ModelError(f"{where}: 'at' needs one formula per dimension of {t.name} ({', '.join(t.dims)})")


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


def load_scenario(path: str | Path, extra_mods: list[str | Path] = ()) -> Scenario:
    """A scenario file; `extra_mods` come after the scenario's own `mods` (stage S7.1)."""
    path = Path(path)
    doc = tomllib.loads(path.read_text(encoding="utf-8"))
    head = doc["scenario"]
    commands: dict[int, dict] = {}
    for command in doc.get("command", []):
        commands.setdefault(int(command["step"]), {}).update(command["set"])
    mods = head.get("mods", [])
    if not isinstance(mods, list) or not all(isinstance(m, str) for m in mods):
        raise ModelError("[scenario] mods must be a list of folders")
    mods = [path.parent / m for m in mods] + [Path(m) for m in extra_mods]
    return Scenario(path.stem, load_model((path.parent / head["model"]).resolve(), mods), int(head["seed"]),
                    int(head["steps"]), head.get("preset", "central"), doc.get("params", {}),
                    doc.get("levers", {}), commands)
