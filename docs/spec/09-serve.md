# `polisim serve`: runs driven line by line

Stage S14.2. The tests in `tests/` and the UK tools (`tools/uk/hindcast.py`, `calibrate.py`,
`screen.py`) drive the engine through this protocol, by way of `tools/engine.py`. It is for
tests and tools, not for the game, which links the engine directly.

```text
polisim serve <scenario.toml | model folder> [--mod DIR]... [--seed N] [--preset P]
```

One process serves one model, loaded once, and any number of runs of it. It reads one
request per line on standard input and writes one reply per line, a JSON object, on
standard output. The first line is written before any request: `{"ok":true,"model":ID,
"model_hash":HEX}` if the model loaded, otherwise the error (below) and the process ends
with exit code 1. The session ends at the end of the input or at `quit`.

## Runs

Run 0 starts with the session: the scenario's settings, or seed 0 and the central preset
for a model folder, with `--seed` and `--preset` applied on top. `open` starts another run
and replies with its number. A request is about run 0 unless it starts with `@N`, the run's
number: `@2 step 12`. A run that could not start answers every request about it with the
error that stopped it, until `new` starts it again.

## Requests

Values are written as TOML values: `0.25`, `15000`, `true`, `"low"`, `{seed = 3}`.

| Request | Reply | What it does |
|---|---|---|
| `open SETTINGS` | `{"ok":true,"run":N}` | Starts a new run. SETTINGS is an optional table: `seed`, `preset`, `params` (a table), `levers` (a table), each optional (seed 0, `central`, the model's own values). A run that cannot start is not kept |
| `new SETTINGS` | `{"ok":true}` | Starts the addressed run again with these settings |
| `close` | `{"ok":true}` | Ends the addressed run; its number is used again |
| `set NAME VALUE` | `{"ok":true}` | Changes a lever, or answers a dilemma, at the start of the next step: a command for that step (engine contract, section 6). It is checked, and voted on as a bill, when the step runs. For one lever in one step the last `set` wins |
| `step [N]` | `{"ok":true,"rows":[...]}` | Runs N steps (default 1). Each row is an object: `step`, `hash` (the state hash in hexadecimal), then every national value and sector total in the order of `polisim run`'s columns |
| `get NAME` | `{"ok":true,"value":V}` | A value now: one number for a national value, a list for one with a value per record or per cell (in the order of the records, or of the cells, row-major) |
| `evaluate {formula = "..", entity = "..", type = "real", unit = "1"}` | `{"ok":true,"value":V}` | Evaluates a formula against the current state, as `Simulation::evaluate` does: one value, or one per record of `entity`. `type` is `int`, `real` or `bool` (default `real`), `unit` defaults to `1` |
| `votes` | `{"ok":true,"votes":[...]}` | Every vote so far: `step`, `lever`, `value`, `for`, `seats`, `passed`, `cost` (null without political capital), `refused` |
| `model` | `{"ok":true,...}` | The model: `id`, `format`, `currency`, `minor`, `model_hash`, `phases`, `dims` (`name`, `first`, `members`, `labels`), `entities` (`name`, `ids`, `weights`, `weight_state`), `accounts` (`name`, `sector`, `instrument`), `dilemmas` (`name`, `label`, `doc`, `again_after`, `options`), `mods` and `mod_notes` |
| `symbols` | `{"ok":true,"symbols":[...]}` | Every symbol in declaration order: `name`, `kind`, `type` (`int`, `real` or `bool`; money is `int` with `money` true), `money`, `unit`, `entity`, `phase`, `dims`, `range`, `initial` and `spec`, the symbol's table as the model files give it |
| `scenario` | `{"ok":true,...}` | The scenario's `name`, `seed`, `steps`, `preset`, `params`, `levers` and `commands` (`[step, lever, value]`); an error when serving a model folder |
| `quit` | none | Ends the session |

## Values

Whole numbers are written as whole numbers, money in minor units. Reals are written in
the shortest form that reads back to the same value, always with a decimal point or an
exponent (`1.0`, `0.1`, `1e+16`), so they keep every bit and stay apart from whole numbers.
Infinities and not-a-number, which `evaluate` can give, are written `Infinity`,
`-Infinity` and `NaN`: not standard JSON, but what Python's `json` module reads and
writes. Booleans are `true` and `false`.

## Errors

A request that fails is answered with `{"error":MESSAGE,"kind":KIND}` and the session
carries on. KIND is the engine's: `model` (the model or the settings are inconsistent),
`formula` (a formula is malformed), `run` (a step or an evaluation produced an illegal
value), or `request` (the request itself: an unknown request, name or run number). A
failed `step N` also gives the rows of the steps completed before the failure, as
`"rows"`. The engine's messages are the ones `polisim run` prints.
