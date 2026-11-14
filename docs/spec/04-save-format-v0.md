# Save format 0

A save is a snapshot taken between two steps. It holds everything needed to continue the
run, and nothing that can be recomputed. The implementation that defines it is
`crates/core/src/save.rs`. The Python oracle does not read or write saves; the guarantee
below is tested against the engine itself.

Related: [engine contract](00-engine-contract.md).

## Guarantee

Loading a save and continuing gives exactly the run that was never interrupted: the same
state hash on every later step. A save taken straight after loading is byte for byte the
save that was loaded.

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
| format | `u32`, currently 0 |
| engine version | text, informational |
| model hash | 32 bytes |
| seed | `u64` |
| steps completed | `u64` |
| state hash | 32 bytes |
| parameter count | `u32` |
| each parameter | name (text), type (`u8`), value; a dimensioned parameter (format 1 models) has type 3, 4 or 5 (whole, real, true/false), then a count (`u64`) and that many values in row-major order |
| value count | `u32` |
| each value | name (text), type (`u8`), shape (`u8`), count (`u64`), then `count` values |

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

## Not in format 0

Compression, a command log (so that a save can also be replayed from the start), mod
lists, and migration between model versions. A save belongs to one exact model: change
any model file and existing saves stop loading. That is deliberate for now and will need
a migration story before anything is released.
