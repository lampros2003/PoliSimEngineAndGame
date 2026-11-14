# Playing PoliSim (test build)

You are the head of government of Valmora, an invented country of about eight million
households, for one five-year term. The economy is small on purpose: households, firms
and a government, and one kind of money. It is here to test the game, not to model a
real country; that starts with the United Kingdom in the next stage.

## Starting

On Windows, unpack the download and run `PoliSim.bat`. Windows may warn that the
publisher is unknown, because the build is not signed: choose "More info", then "Run
anyway". The game opens at the start of January 2027.

## The screen

| Part | What it shows |
|---|---|
| Top bar | The month just finished, and buttons to advance one month, a quarter or a year |
| Headline | Output (GDP), unemployment, the budget balance and public debt, with last month's change |
| Budget | Every payment into the government (revenue) and out of it (spending), this month and last |
| Policy | Your six levers. Type a new value; it shows in amber and takes effect next month. Undo cancels it |
| Chart | Any figure over time. Dashed lines are your policy changes. Click a name in the legend to remove it |
| Why did it change? | What moved a figure last month, input by input. Press an input to follow it; Back returns |

Every amount is in crowns (Cr). "A month" means a monthly flow; output of Cr 39bn a month
is about Cr 470bn a year.

## Things to try

1. Advance a year without touching anything, then press **Why** next to the budget
   balance. The parts add up exactly to the change.
2. Cut government purchases by Cr 1bn and advance a month. Spending falls by exactly
   that amount and the budget improves by about as much. Advance two more years and
   watch unemployment and benefit spending: most of the saving disappears, because
   firms sell less, hire less and the government pays more benefit.
3. Raise the basic income tax rate and follow **Why** from income tax receipts down to
   "income before tax" to see the tax base shrink as people lose work.
4. Chart output and household spending together, then make a change: the dashed line
   marks the month it took effect.

## Saving

**Save** keeps one saved game, including its charts. **Load** returns to it. A saved game
belongs to the exact model files it was made with: change the model and old saves will
not load, by design for now.

## Changing the model while playing

The economy is written in text files in `game/models/valmora/` (the formats are in
`docs/spec/` of the repository). Edit a number or a formula, save the file and press
**Reload model**: the change takes effect from the next month, with everything else
carried over. If the file has a mistake, the game says what and where at the bottom of
the screen and carries on with the previous version.

## Known limits of this build

- The household sample has only 1,000 records, so unemployment jumps by up to a point
  from month to month. Larger samples come in stage S4.
- Nothing limits supply except the number of households, so spending more always raises
  output. A supply side comes with the first real country.
- There are no elections, parties or legislature yet (stage S5).
- The build is not signed and runs inside the Godot engine executable, not as a
  standalone program.
