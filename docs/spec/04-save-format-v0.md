# Save formats 0 and 1

A save is a snapshot taken between two steps. It holds everything needed to continue the
run, and nothing that can be recomputed. The implementation that defines it is
`crates/core/src/save.rs`. The Python oracle does not read or write saves; the guarantee
below is tested against the engine itself.

Related: [engine contract](00-engine-contract.md).

## Guarantee

Loading a save into the model it was made with and continuing gives exactly the run that
was never interrupted: the same state hash on every later step. A save taken straight
after loading is byte for byte the save that was loaded.

Format 1 (stage S7.0) also lets a save follow the model when its files change: see
"Loading into a changed model" below. The engine writes format 1 and reads both.

## What is stored

- the hash of the model the run belongs to;
- the seed and the number of completed steps;
- the state hash at the time of saving;
- the resolved value of every parameter (after presets and overrides);
- the persistent state: every lever, account, state and `prev()`-read variable or flow,
  which is exactly the set the state hash covers, in the same order.

Not stored: the model, data columns, values recomputed each step, and commands still to
come. A session that resumes supplies its remaining commands again.

## Layout

All integers are little-endian. Text is UTF-8 preceded by its length in bytes as a `u16`.

| Field | Encoding |
|---|---|
| magic | the 8 bytes `PSIMSAVE` |
| format | `u32`, currently 1 |
| engine version | text, informational |
| model hash | 32 bytes |
| seed | `u64` |
| steps completed | `u64` |
| state hash | 32 bytes |
| parameter count | `u32` |
| each parameter | name (text), type (`u8`), value; a dimensioned parameter (format 1 models) has type 3, 4 or 5 (whole, real, true/false), then a count (`u64`) and that many values in row-major order |
| value count | `u32` |
| each value | name (text), type (`u8`), shape (`u8`), count (`u64`), then `count` values |

Format 1 then says what each value is:

| Field | Encoding |
|---|---|
| dimension count | `u32` |
| each dimension | name (text), member count (`u32`), each member (text) |
| entity count | `u32` |
| each entity | name (text), the SHA-256 of its record ids as little-endian `u64`s (32 bytes) |
| each value, in the order above | kind (`u8`: 0 var or flow, 1 lever, 2 account, 3 state), entity (`u32` index, or `u32::MAX` for none), dimension count (`u8`) and each dimension (`u32` index) |

Type is 0 for a whole number, 1 for a real, 2 for true/false. Shape is 0 for one national
value (count is 1) and 1 for one value per record, or per cell of a dimensioned value in
row-major order. A whole number is 8 bytes two's complement, a real is the 8 bytes of its
IEEE 754 pattern, true/false is one byte.

## Loading

Loading fails, and nothing is resumed, when:

- the file does not start with the magic bytes, or its format number is unknown;
- its model hash is not the hash of the model it is being loaded into;
- it ends early or has bytes left over;
- its parameters or values do not match the model's declarations by name, type, shape or
  record count;
- a value is outside its declared range;
- the state hash recomputed after loading differs from the one stored.

The last check means any change to a stored value is detected, whether from damage or
from editing.

## Loading into a changed model

Stage S7.0. When the model hash differs, a format 1 save still loads, and the run carries
on with the new model:

- a new run is built for the model, with the save's seed, and parameters from the model
  at the scenario's preset and overrides, as for a new game (a model update brings its
  calibration with it);
- each of the model's persistent values takes the saved value of the same name, or of the
  name it had before a rename the model declares (`[renamed]`, model format 1), when the
  two are the same kind of element (var or flow, lever, account, state), belong to the
  same entity with the same record ids (by hash) or to the same dimensions with the same
  members in the same order, and have the same type;
- a lever whose saved setting is outside its new range is moved to the nearer end of it;
  any other carried value outside its range is not carried;
- everything else starts from its initial value, and saved values the model no longer
  has are dropped;
- the number of completed steps is the save's; the state hash is computed afresh.

The loader reports how many values it carried, which started again, which levers it moved
and which values it dropped or found under a new name; the client tells the player. A
format 0 save loads only into the model it was made with. These are the rules hot reload
already followed (engine contract), now shared by both.

## Not in format 1

Compression, a command log (so that a save can also be replayed from the start), and mod
lists (the model hash covers the mods' files, stage S7.1).
