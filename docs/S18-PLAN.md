# Stage S18: the look, to the genre's standard

## Context

The owner asked on 2026-11-28 to bring the game up to the best of its kind, to improve the
graphics, to work as a top professional would, and to use what is openly available rather
than build from scratch. S16 and S17 measured the screen (contrast, spacing, fit, the
keyboard). This stage is about what it looks like. It is client work with one new data file;
no model, engine or bridge change, and no recorded hash moves.

What the best political and strategy simulations have that this one lacked, set against our
own pictures at 1366x768, 1440x900 and 1920x1080:

| The genre's best | Here, before this stage |
|---|---|
| Vector artwork that is sharp on any screen and at any size | Every pictogram was one 512 px picture shrunk to 16 to 40 px: soft at 1x, and S17's status already said "the smallest pictograms are ragged". Discs had stepped edges. Words along the rim went soft when turned |
| A picture for each event: the question put, election night, the end of a term | Text only, on a blank sheet |
| The country as a map | A table of seven rows |
| The basics of a finished program: its own icon, an opening picture, the whole screen | The engine's icon, the engine's splash, a window only |

## Decisions

| Question | Decision |
|---|---|
| The art direction | Kept: pictorial statistics in the manner of mid-century public-information print (warm paper, five flat inks, hard shadows, Jost and IBM Plex Sans). The stage raises the finish of that style; it does not change the style |
| Sharpness | The engine's own scalable importer for drawings (Godot's `DPITexture`), not a rasteriser of ours: each pictogram is made from its drawing at the size it is shown and at the screen's scale, and kept. Discs are drawn anti-aliased. Words along a curve use a distance-field copy of the face, which the engine also provides |
| Pictures for events | A **plate**: a poster-style head made from the open pictograms the game already uses (game-icons.net, CC BY 3.0), a tone and rays. No commissioned or generated art, and nothing drawn for one event: a scenario gives a question its plate in one line (`[play.plates]`), and a mod's question gets a plain one with none |
| The map | Open boundaries from the Office for National Statistics (ITL1, January 2025; Open Government Licence v3.0), thinned with the open tool mapshaper (MPL-2.0) by `tools/uk/map.py`, kept as plain GeoJSON beside the model (`models/uk/map`). The scenario names the file and says which regions make each of its places. It stands on the Parliament sheet beside the House, in view whichever section is open |
| The map's colours | One hue, light to dark, in five bands of ten points from nought to a half: the scale of the bars beside it. A place with no figure is hatched, not tinted. The exact figures stay in the table; pointing at a place names it and gives its figure |
| The program's own pictures | The icon and the opening picture are painted by the plate's own code (`client/tests/make_art.gd`), so they match the game. F11 and the menu switch between the whole screen and a window, and the choice is kept |
| Textures, motion, music | Looked at and left for the owner to ask for: a paper texture (ambientCG, CC0) would sit under every piece of text whose contrast S17 measured against the flat paper; motion and music are a matter of taste best judged on his machine |
| Speed | The budgets of `client/tests/perf_check.gd` hold unchanged |

## Open material used

| What | From | Licence | Where it is credited |
|---|---|---|---|
| 15 more pictograms (bank, flood, foundry bucket, handcuffs, shaking hands, laurels, power lightning, megaphone, money stack, podium, processor, sailboat, snowflake, tap, thermometer) | game-icons.net, by Lorc and Delapouite | CC BY 3.0 | `client/icons/CREDITS.md`, and How to play |
| The United Kingdom's regions | Office for National Statistics, Open Geography Portal: International Territorial Level 1 (January 2025) Boundaries UK BUC | Open Government Licence v3.0; contains OS data © Crown copyright and database right 2025 | `models/uk/map/README.md`, the file itself, `docs/data/first-country-licences.md`, and How to play |
| mapshaper 0.6.121 (a tool; nothing of it ships) | github.com/mbloch/mapshaper | MPL-2.0 | `tools/uk/map.py` |
| Scalable drawings, distance-field type, anti-aliased drawing | Godot 4.7 | MIT | — |

## Stages

| # | Stage | Lane | Done when |
|---|---|---|---|
| S18.1 | Sharp at every size | Client | Every pictogram on every card and on the board is made at the size it is shown (held by `folds_check.gd` and `contrast_check.gd`); discs anti-aliased; before and after pictures read |
| S18.2 | The program's own pictures and the whole screen | Client | The game has an icon and an opening picture; F11 and the menu switch to the whole screen and back, kept between sessions (`feel_check.gd`, `plates_check.gd`) |
| S18.3 | Plates | Client, scenario | Every question of the UK model, election night won and lost, the end of a term and the start screen has a plate; every pictogram is credited (`plates_check.gd`) |
| S18.4 | The country as a map | Client, data | The map reads, fills and covers every place; the pointer and the table are linked; the acknowledgement is shown (`map_check.gd`) |
| S18.5 | Verify | All | Every older check passes with the new ones; pictures at two sizes read; documents brought up to date |

## Status

| # | Status |
|---|---|
| S18.1 | Done (2026-11-28). The 159 pictograms are imported as drawings (`importer="svg"`) and `Palette.icon(name, px)` and `Palette.sized` hand back one made at the size asked for, kept by drawing and size; the board asks at each node's own size and snaps it to the pixel grid. `Palette.unsharp` lists any picture on a card whose made size is not the size it is shown at, and `folds_check.gd` (every card and fold at two sizes) and `contrast_check.gd` fail on one. The discs and dots of the board, the charts, the group cards and the House are drawn anti-aliased. The rim's words use `Palette.display_turned` (a distance-field copy of Jost); upright words keep the ordinary face, which is crisper at small sizes |
| S18.2 | Done (2026-11-28). `client/icon.png` (256 px) and `client/splash.png` are painted by `tests/make_art.gd` from the plate's code and named in `project.godot`. Full screen: F11, and Menu, "Full screen"; kept in the settings file; the automatic size of the interface is worked out again for the new height |
| S18.3 | Done (2026-11-28). `scripts/plate.gd`; `[play.plates]` in the UK scenario gives one to each of the model's 15 questions and to `election`, `election_lost` and `term`; the start screen carries one. `plates_check.gd` holds the table against the model, the pictograms against `client/icons`, and the credits against the files, both ways |
| S18.4 | Done (2026-11-28). `scripts/country_map.gd`, `models/uk/map/regions.geojson` (12 regions, 973 points, 34 kB) made by `tools/uk/map.py`. The Parliament sheet is two columns, 1000 px wide: the House and the sections, and the map. `map_check.gd` holds that every region is in exactly one place and can be filled, that the bands are at least 1.3 to 1 apart in luminance (they are 1.45 to 1.67), that the land and its key are inside the sheet at 1366x768 and 1920x1080, that a point in each place is found there, that each place is in the band of its own figure with Northern Ireland hatched, the pointer and press, the acknowledgement in How to play, and that a map which cannot be read leaves the table alone |
| S18.5 | Done (2026-11-28). `tools/check_client.py` passes whole: the 35 older lines and the two new checks, with the speed budgets as written (a popup open in 77 ms against 120, a month in 91 against 165 on this machine's stretched budget, a keystroke in search 1.6 against 4). The 229 behaviour tests pass and every recorded hash is the same, as it must be with no model or engine change. Pictures of the start screen, the board, Parliament with each section, a question and election night were taken at 1366x768 and 1440x900 and read; what they showed is in the two lists below |

**Found on the way and fixed**, each with the check that keeps it fixed:

- After a sheet was opened with nothing on the top bar changed, the search's button was left as
  wide as its field and lay over Add policy (from S17.1's fitting of the bar: the field grows
  at once when tried at its wider sizes, and a fit that ends where it began changed no least
  size, so nothing laid the row out again). The row is now laid out after every fit;
  `bar_check.gd` opens and shuts both sheets and fails if two pieces of the bar overlap. It
  failed before the fix.
- The month's report was drawn over the sheets, not under them as its own comment said, so in
  a month with an election or a question it covered the left of that sheet at 1440 wide and
  under. It is now under them (`plates_check.gd`).
- The gilt crisis, the model's fifteenth question, had no plate in the first table.

**Seen and left**, with the reason: the map is worked with the pointer only (the keyboard
reads the same figures in the table beside it); at 1366x768 the table of places still scrolls
inside the sheet, as the table of groups does; the board's crowded labels at 1366 wide stand
as S17 left them; a build exported to a single pack file would need `*.geojson` added to its
export filter (the Windows test build ships the folders as they are).
