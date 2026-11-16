# Stage S17: the second polish pass

## Context

S16.1's polish pass listed 24 faults and fixed 20, and said what it had not covered. The owner
asked on 2026-11-16 for a second pass. This stage is that list, each item with a check that
keeps it fixed. It is client work only: no model, engine or bridge change.

## Decisions

| Question | Decision |
|---|---|
| The top bar's figures | Approval and political capital stay first and last to give way. At 1920 wide every headline figure shows (Budget balance, Debt to GDP, growth, unemployment). Before any figure gives way, the search field shrinks to its button. Figures then give way one at a time in a stated order, least important first |
| Contrast | Measured, not judged: every pair of text colour and ground the client uses, by the WCAG 2.1 ratio. Text 4.5 to 1; text of 18 px or more, and marks that carry meaning (gauges, link colours, pennants), 3 to 1. A scripted check holds the pairs so a later palette change cannot break them |
| Spacing | One scale (4, 8, 12, 16, 24, 32 px), named once beside the palette. Margins and gaps off the scale are moved to it; a number that must be off it says why in a comment |
| The keyboard | Tab goes through every sheet and popup in reading order and stays inside it while it is open; every control that can be reached shows a focus ring; Esc closes the topmost thing and focus returns to where it was. A scripted check walks each sheet |
| Folds | Every fold of every kind of popup (policy, statistic, group of voters, situation) is opened and photographed at 1366x768 and 1920x1080 and gone through against S16's checklist |
| The Budget's totals | Set by the layout, not by spaces |
| The wealth-tax mod | The start screen stops offering a mod that doubles a policy the model already has. Mods are still proved to work by a check, with a mod that adds something the model lacks. No model hash changes |
| S16's four unfixed faults | Each is fixed or has its reason written in the Status row |
| Group names on the ring | Not tried a third time: 26 names do not fit a ring this size. They stay on hover and in search |
| Speed | The budgets of `client/tests/perf_check.gd` hold unchanged |

## Stages

| # | Stage | Lane | Done when |
|---|---|---|---|
| S17.1 | The second polish pass | Client | The contrast, focus and top-bar checks pass with every older check; the list of faults found and fixed; screenshots of every fold at two sizes read |

## Status

| # | Status |
|---|---|
| S17.1 | Not started |
