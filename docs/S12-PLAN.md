# Stage S12: pages, the policy web, political capital and a map

Written 2026-11-14, after S11 and the client's new look, at the owner's request: a
cause-and-effect graph like the genre's (Democracy is the project's inspiration), pages,
policy categories, policies that cost political capital to enact, and, second, a map with
statistics. The owner chose: capital as an engine rule, a tile map of the twelve regions
and nations, and Lucide icons.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Pages | A navigation strip under the masthead: **Policy**, **Budget**, **Who gains, who loses**, **Politics**, **Policy web** and **Map**, with the political capital at its right. The headline figures stay at the top of every page, and the chart and "Why did it change?" on the right of every page (the web was first to take the whole width; it fits beside them, and pressing a node explains it there) | One long scrolling column held four panels; a page each lets each one breathe, and "Chart" and "Why" still work from anywhere |
| Policy categories | The Policy page opens on a grid of the model's lever `group`s: icon, name, number of policies, changes waiting. A category opens its policies, with Back | The groups are already in every model (eleven in the UK); nothing new is needed in model files |
| What the web shows | Our own layout, not the genre's ring of icons: three bands left to right: **policies** (the player's levers, by category), **outcomes** (the figures a model's `[play]` lists, its situations, and what links them), **people** (support for the governing blocs and the headline figures). A link is drawn where a policy reaches an outcome through any chain of formulas; the chain itself is shown in "Why". Pointing at a node lights its links; pressing it explains it | The catalogue already gives every entry's inputs; collapsing chains keeps a 500-entry model readable |
| Icons | Lucide (ISC licence), pinned to 0.460.0, one per UK category and per page, stroke recoloured in the theme's ink. A model names a category's icon in `[play] icons`; a category without one gets a plain square | Icons belong to the model's content, as labels do; another model can bring its own |
| Political capital | Format 1 extends `[legislature]` with `capital` (a real national state), `spent` (a real national lever the engine sets, not the player), `bill_cost` and `swing_cost` (real national parameters). A bill costs `bill_cost + swing_cost * weight * abs(new - old) / (max - min)`, where `capital_weight` is an optional lever key (default 1; named so, not `weight`, to keep clear of household weights) and the range is the lever's (no range: `bill_cost` alone). In part 1 of a step, bills are taken in command order; a bill that costs more than the capital left (the state's start-of-step value less what bills before it in the step spent) is **refused**: not voted on, not applied, not an error. A bill that is voted on and passes spends its cost; a defeated one spends nothing. After part 1 the engine sets `spent` to what the step's bills spent (0 if none); the model's own formula for `capital` reads it | The same place, the same order and the same exactness as bills (S5.4), so oracle and engine agree by construction; how capital is earned stays in the model, where it can be tuned and modded |
| How the UK earns capital | `capital.toml` in `models/uk` (written by hand, not generated): 40 at the start, at most 100; each month `1 + 5 * clamp((support - 0.25) / 0.20, 0, 1)` where support is the government's poll rating, plus 2 in the first year of a parliament. Any bill costs 5, a full-range move of a lever 60 more (a point on the basic rate 5.6, five points of VAT 11). Every UK lever weighs 1 for now: the levers are in generated files, so weights wait for the generators | A popular, new government can do more; a big change costs more than a small one. A first try (60 at the start, 3 a bill, 40 a range, up to 10 a month) let the government pass two bills a month and reach the ceiling by May 2025, so it was halved; numbers are judgements, to be tuned in play |
| Saves | The session file records each change's cost and whether it was refused (session version 4); version 3 files load with costs unknown | Saves keep every vote now; refusals are votes that never happened |
| The map | The twelve regions and nations as a tile cartogram, laid out by hand in the client (no boundary data), coloured on one blue scale by any statistic the scenario's `[play] breakdowns` gives by region, with a legend and each tile's value | No outside data or licence question; constituencies can follow with ONS boundaries (OGL) later |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S12.1 | Pages and categories | The navigation strip, the six pages, the category grid and category pages; every client check passes |
| S12.2 | Icons | Lucide SVGs for the UK's eleven categories and the pages, imported, recoloured, shown; the licence beside them |
| S12.3 | The policy web | The three-band web from the catalogue, highlighting and "Why" on press; a scripted check walks it |
| S12.4 | Political capital in the rules | Spec 06 and the engine contract, oracle, engine, shared bill cases, the UK's `capital.toml`, regenerated UK recordings; engine against oracle on random and UK scenarios |
| S12.5 | Political capital on screen | The capital in the masthead with its monthly gain, each change's cost before you make it, refused bills announced, saves version 4 |
| S12.6 | The map | The tile map page with a choice of statistic, legend and values |

## Status

| # | Status |
|---|---|
| S12.1 | Done. `main.gd` builds a navigation strip (`NavBar`, `NavItem` in `palette.gd`) and a page per panel in a `TabContainer` without tabs; `show_page(key)`. The Policy page (`lever_panel.gd`) opens on a grid of tiles, one per lever `group` ("Other" for none), with the number of policies and changes waiting; `open_category(group)` shows that area's policies with a link back. The folding groups are gone |
| S12.2 | Done. 20 Lucide 0.460.0 icons (ISC, `client/icons/LICENSE-lucide.txt`), drawn white at 48 px and tinted by the theme; `[play.icons]` in `models/uk/scenarios/2025.toml` names one per UK area; `Palette.icon(name)` falls back to a square |
| S12.3 | Done. `policy_web.gd`: areas (or one area's policies), 13 UK outcomes and 17 situations and support, linked where a lever reaches a node through formulas that pass no other node on the web; links faint until pointed at; areas open, other nodes explain. `tests/policy_web_check.gd` (in `tools/check_client.py`) checks the pages, the areas and the web |
| S12.4 | Done. Spec 06 ("Political capital") and the engine contract; oracle (`model.py`, `sim.py`) and engine (`model.rs`, `sim.rs`) refuse a bill that costs more than is left and set `spent`; 13 shared cases in `conformance/bill_cases.toml` (a `capital = true` case applies the file's `capital` replacements), run by both; the UK's `capital.toml`, its `[legislature]` (in `tools/uk/voters.py` and `politics.toml`) and file list (`tools/uk/calibrate.py`, `model.toml`); the four UK recordings regenerated by the oracle and matched by the engine. Over the first year the UK earns about 5.2 a month, about 3 after |
| S12.5 | Done. The session keeps each change's cost and refusal (session file version 4; older files load with no cost); the bridge gives `bill_cost(lever, value)` (the engine's own formula), each change's `cost` and `refused`, and the catalogue's `capital` and `capital_spent`. The capital shows at the right of the page strip with last month's change and what the bills waiting will cost; each waiting change shows its cost; the Policy page warns when the bills waiting cost more than there is; refused bills are announced. `tests/capital_check.gd` and an engine test (two 41-capital bills, the second refused, kept through a save) |
| S12.6 | Done. `map_panel.gd`: `[play.map]` gives the dimension, the statistics (UK: net income, unemployment and income tax by region) and each member's tile; tiles shaded from pale to navy, lowest to highest, with values and a legend. Checked in `tests/policy_web_check.gd` (twelve tiles, London's net income darkest) |
