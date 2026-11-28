# Stage S19: show, don't tell

## Context

The owner said on 2026-11-28, after S18: improve the interface for usability and readability;
"show dont tell, you should not have explainer notes on everything always remember this, ui
should be intuitive not patronisingly explained". The rule is now a standing one, written at
the head of `docs/PLAN.md`, Decisions.

Until this stage the client explained itself in sentences. Counted in its scripts before the
stage: 23 standing notes on cards and sheets (under a policy's controls, under a group's
bars, under the month's report, under Parliament's scales, on the start screen), a help
sheet of nine paragraphs, a key of five paragraphs, a guide of five paragraphs, and two
sentences where Parliament's figures should have been. Client work only: no model, engine or
bridge change, and no recorded hash moves.

## Decisions

| Question | Decision |
|---|---|
| What counts as telling | A sentence that says how to use a thing, or what a thing is where a label, a figure, a state or a shape would do. It is removed, and where it carried something true that is now shown: by the ends of an axis named, a column headed, a chevron on what opens, a figure under its name |
| What stays in words | Content: the model's own description of a policy or a statistic (its head, the rest under the pointer), a question's choices, a consequence about to happen ("The Commons would vote it down, 250 to 380"). And what the player asks for: a tooltip, the key, the keys |
| Parliament's standing | Figures under their names (government, seats, polls, turnout; health, education, policing and the environment since the election), not two sentences |
| Help | The keys and the credits. How to play is not written down: the board is to be understood by using it, and "?" is its key |
| The key | A legend: each sample with a line of a few words, not a paragraph |
| The guide | Kept for a first game, each step a few words |
| Keeping it so | `folds_check.gd` walks every card and fold and fails on a piece of muted text over 72 characters that is not the model's own words |

## Stages

| # | Stage | Lane | Done when |
|---|---|---|---|
| S19.1 | Strip the explainer notes | Client | Every standing note gone or shown another way; the lint passes on every card |
| S19.2 | Figures and affordances in place of sentences | Client | Parliament's figures; help as keys; the key as a legend; a chevron on the report's lines |
| S19.3 | An independent reading of the pictures | Client | Two reviewers, given the pictures and the owner's rule and no account of what was changed, list what a player would misread; what is real is fixed or listed with its reason |
| S19.4 | Verify | All | Every check passes; documents brought up to date |

## Status

| # | Status |
|---|---|
| S19.1 | In progress |
| S19.2 | In progress |
| S19.3 | In progress |
| S19.4 | Not started |
