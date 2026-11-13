# Project owner's decisions (ballot submitted 2026-11-13)

These are the project owner's answers to 22 founding design questions. They are **constraints on the
recommendations**, not research findings. Where the research supports a decision, say so. Where the
research gives reason to doubt a decision, say that plainly and explain the trade-off; the owner asked
not to be followed uncritically. All 22 questions were answered; none was left blank.

| # | Question | Decision | Owner's own words (write-in) |
|---|----------|----------|------------------------------|
| 01 | World scope | One country in detail, plus a few coarse trading blocs (3 to 10 simplified partner economies) | |
| 02 | Setting | Data-agnostic engine; ship one real country built from real data first, others as scenarios | |
| 03 | Time | Monthly simulation steps, turn-based (player advances a month or a quarter); slow processes may step yearly | |
| 04 | Political layer | Voters and elections **plus parties and a legislature** (seats, coalitions, votes on bills, a reacting opposition). Not the full machine of ministers, factions, media, lobbies | |
| 05 | Population | **Hybrid**: cohort tables for demography (births, deaths, ageing, migration) plus a weighted sample of simulated households for income, tax, benefits and voting | |
| 06 | Economy | **Hybrid**: stock-flow consistent sector balance sheets + multi-industry production (input-output), fed by the household sample for demand, labour and taxes | |
| 07 | Geography | 10 to 50 regions | "10 to 50 regions depending on the actual regional breakdown of the country" (i.e. follow the country's real administrative/statistical regions) |
| 08 | Rigor | Calibrated start year, dynamics sanity-checked against a few historical episodes; gameplay wins on conflict | |
| 09 | Economic schools | Disputed parameters (fiscal multiplier, tax elasticities, etc.) are scenario settings with low/central/high values | |
| 10 | Build order | **A thin slice of everything**: minimal engine core in the final language + tiny real model + throwaway interface, growing together; benchmarks decide what to optimise. (The owner originally proposed engine-first and changed to this on the ballot.) | |
| 11 | Engine language | Left to the research | "I am mostly in favor of rust as well but leave to research" |
| 12 | Model authoring | Data files plus a small formula language, compiled at load time into a flat execution plan | |
| 13 | Reproducibility | Strict: bit-identical on every machine for the same seed and inputs | |
| 14 | Hardware | Mid-range laptop, CPU only; a turn resolves in well under a second | |
| 15 | Client | Godot 4 with the engine as a native extension | |
| 16 | Platforms | Windows and Linux only (macOS, Steam Deck, web and mobile were not selected) | |
| 17 | Modding | First-class: the base game is itself a mod; all content in documented, hot-reloadable data files | |
| 18 | Multiplayer | Single-player now, keep the door open | |
| 19 | Team | One person, part-time | "be ambitious though" |
| 20 | Experience | Comfortable in Rust, comfortable in C/C++, also uses higher-level languages; **Claude (an AI coding assistant) writes most of the code while the owner directs and reviews** | |
| 21 | Goal and licence | Commercial game, closed source for now | "we will probably open source the engine but start like this for now" |
| 22 | Horizon | No deadline | "as long as it takes" |

## What this implies for the report

- The option space is now narrow. The report should spend its depth on **how to build the chosen design
  well** and on the decisions still open, and treat rejected options briefly (why they lose, and when
  they would win instead).
- Still open and to be settled by the research: **engine language** (owner leans Rust), the concrete
  shape of the formula language and execution plan, population sample size and cohort dimensionality,
  number of industries and trading blocs, which real country to build first (data availability and
  licensing should drive this), how parties/legislature are represented in the engine, and the staged
  roadmap.
- Constraints to respect throughout: solo part-time developer with heavy AI coding assistance and no
  deadline but high ambition; CPU-only mid-range laptop; strict cross-machine determinism; Windows and
  Linux; Godot 4 client via native extension; first-class moddability; closed source now with the engine
  likely open-sourced later (so keep engine/game separation clean and dependency licences permissive);
  multiplayer not planned but not to be designed out.
- The owner asked for a critical view. If the evidence says any decision above is risky for a solo
  part-time project (for example the combined scope of hybrid population + SFC/IO economy + regions +
  legislature + calibration), say so and propose how to stage it.
