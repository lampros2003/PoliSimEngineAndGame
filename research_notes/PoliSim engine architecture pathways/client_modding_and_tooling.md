# Client, binding, modding formats and tooling around a headless simulation core (state as of November 2026)

Research conditions that affect confidence (read first):

- Research date: 2026-11-13. Version numbers below were read from GitHub release pages (direct fetch) or from search-engine summaries of official pages.
- Direct fetching worked only for github.com. godotengine.org, bevy.org, unity.com, unrealengine.com, webassembly.org, godot-rust.github.io and similar hosts were not reachable from this session, so facts attributed to those sites come from search-result summaries of them, not from a full read of the page.
- The shared web-search budget ran out before the last planned searches (Minecraft datapacks, OpenTTD NML language detail, Stellaris specifics, Modelica/SBML/NetLogo/GAMS status, WebGPU browser status, localisation pipelines, Shadows of Doubt). Those items are listed under Gaps, or appear under Inferences marked "prior knowledge, not verified this session".
- GitHub release pages show day and month only for some entries; where a year is given as "inferred", it was inferred from ordering against dated releases.

---

## 1. Client / front-end options for a UI-heavy, chart-heavy 2D strategy game (small team, desktop first)

### Takeaway
Godot 4.7 with a Rust core (via godot-rust or a thin C ABI) and a web-technology shell (Electron 45 or Tauri 2 with a TypeScript UI) are the two routes with the strongest current evidence for dense UI; Bevy, egui, Iced and Slint are usable but each has a specific gap (Bevy's UI and editor are still being built, egui is immediate-mode, Iced is pre-1.0, Slint has attribution/licence conditions). Unity and Unreal are licence-stable again after the 2023 runtime-fee episode, but the most visible 2025 engine migration of a UI-heavy sim (Football Manager 26 to Unity) went badly on UI, and the most visible success (Slay the Spire 2 on Godot) reported Godot's UI nodes as a weak point.

### Cited Findings

#### Version, date and licence snapshot (November 2026)

| Option | Current version and date | Licence / cost | Source |
|---|---|---|---|
| Godot | 4.7.2-stable, 18 Aug 2026 (4.7 on 18 Jun 2026; 4.6 on 26 Jan 2026; 4.6.3 on 20 May 2026). No 4.8 pre-release was listed on the releases page | MIT (engine); no fees | [Godot GitHub releases](https://github.com/godotengine/godot/releases) |
| godot-rust (gdext) | v0.5.5, 9 Aug (2026 inferred); v0.5.0 on 27 Mar made Godot 4.6 the default; v0.5.4 added the `api-4-7` level | MPL-2.0 (changes to the library must be shared; game code can stay closed) | [gdext releases](https://github.com/godot-rust/gdext/releases), [gdext README](https://github.com/godot-rust/gdext) |
| Bevy | 0.20.1, 28 Oct 2026 (0.20.0 on 8 Oct; 0.19.0 on 18 Jun; 0.18 on 13 Jan 2026) | MIT / Apache-2.0 | [Bevy GitHub releases](https://github.com/bevyengine/bevy/releases), [Bevy 0.18 notes](https://bevy.org/news/bevy-0-18/) |
| bevy_egui | 0.43.2, targets Bevy 0.20 | MIT | [bevy_egui](https://github.com/vladbat00/bevy_egui) |
| egui / eframe | 0.37.0, 15 Oct (2026 inferred) | MIT / Apache-2.0 (not re-read this session) | [egui releases](https://github.com/emilk/egui/releases) |
| Iced | 0.14.0, 7 Dec (2025 inferred); no later release listed | MIT (not re-read this session) | [Iced releases](https://github.com/iced-rs/iced/releases) |
| Slint | 1.18.1, 21 Sep 2026 | Triple: GPL-3.0-only, Slint Royalty-free 2.0, or paid commercial | [Slint releases](https://github.com/slint-ui/slint/releases), [Slint 1.17 licence listing](https://components.espressif.com/components/slint/slint/versions/1.17.0/license?language=en) |
| Tauri | Stable 2.12.5, 21 Oct (2026); 3.0.0-alpha.6 on 6 Nov, with a `tauri-runtime-cef` crate at 3.0.0-alpha.7 | MIT / Apache-2.0 (not re-read this session) | [Tauri releases](https://github.com/tauri-apps/tauri/releases) |
| Electron | 45.3.2, 13 Nov 2026, Chromium 156.0.8078.100 | MIT (not re-read this session) | [Electron releases](https://github.com/electron/electron/releases) |
| Unity | 6.3 LTS (Dec 2025, supported to Dec 2027); 6.4 (Mar 2026). Unity documentation URLs reference 6.6 and 6.7 version strings, not verified as released | Personal free up to $200,000 revenue and funding; Pro $2,310 per seat per year from 12 Jan 2026 | [Unity pricing updates](https://unity.com/products/pricing-updates), [CG Channel on 6.3 LTS](https://www.cgchannel.com/2025/12/unity-6-3-lts-is-out-see-5-key-features-for-cg-artists/), [Unity 6.4 announcement](https://discussions.unity.com/t/unity-6-4-is-now-available/1713245/1), [80.lv on 2026 prices](https://80.lv/articles/unity-announces-its-upcoming-2026-price-changes) |
| Unreal Engine 5 | Version not checked | 5% royalty on a product's gross revenue above $1,000,000 lifetime; 3.5% under "Launch Everywhere with Epic" | [Meta developer page describing the Unreal licence](https://developers.meta.com/horizon/documentation/unreal/unreal-oculus-license/), [EULA provision tracker](https://conductatlas.com/platform/unreal-engine/unreal-engine-eula/provision/CA-P-059597/reduced-royalty-rate-of-35-for-launch-everywhere-with-epic/) |
| SDL3 | 3.4.20, 3 Nov 2026 | zlib (not re-read this session) | [SDL releases](https://github.com/libsdl-org/SDL/releases) |
| Dear ImGui | 1.93.0, 14 Oct (2026 inferred); headline change is an ImDrawList rendering overhaul with breaking half-pixel changes | MIT (not re-read this session) | [Dear ImGui releases](https://github.com/ocornut/imgui/releases) |
| raylib | 6.2, 15 Oct (2026 inferred) | zlib (not re-read this session) | [raylib releases](https://github.com/raysan5/raylib/releases) |
| MonoGame | 3.8.6.1, 4 Nov (2026 inferred); release notes mention Vulkan and DX12 back ends | MS-PL / MIT (not re-read this session) | [MonoGame releases](https://github.com/MonoGame/MonoGame/releases) |
| Defold | Version not shown on the repo page; "completely free to use"; Lua scripting; desktop, console, mobile, web | Defold licence (text not read) | [Defold repo](https://github.com/defold/defold) |

#### Godot 4.x
- Godot 4.6 (January 2026) made Jolt the default 3D physics, Direct3D 12 the Windows default, added a new editor theme and "LibGodot" embedding of the engine as a library — [GameFromScratch](https://gamefromscratch.com/godot-4-6-released/), [AlternativeTo](https://alternativeto.net/news/2026/1/godot-4-6-debuts-modern-theme-jolt-physics-node-ids-and-libgodot-embed)
- Godot 4.7 (June 2026) added HDR output, AreaLight3D, a new Asset Store and a stable Android build environment; 4.7.1 states no known incompatibilities with 4.7 — [80.lv](https://80.lv/articles/godot-4-7-has-been-released), [Godot 4.7.1 post](https://godotengine.org/article/maintenance-release-godot-4-7-1/)
- GDExtension compatibility rule: an extension built for an earlier Godot minor version should work in later minor versions, but not the reverse (a 4.3 extension should work in 4.4; a 4.4 extension will not load in 4.3). godot-cpp is now versioned separately (10.x) and can target 4.3 or later through an `api_version` parameter — [godot-cpp README](https://github.com/godotengine/godot-cpp)
- GraphEdit/GraphNode (the built-in node-graph container) is still flagged "Experimental: this class may be changed or removed in future versions" in the class reference — [GraphEdit docs](https://docs.godotengine.org/en/latest/classes/class_graphedit.html)
- Charts: there is no built-in chart control. The main community add-on, Easy Charts, is MIT, GDScript, offers Control-based area, bar, line, pie, radar and scatter charts, describes itself as "still evolving", and has 789 stars — [Easy Charts repo](https://github.com/fenix-hub/godot-engine.easy-charts)
- Accessibility: Godot 4.5 added screen-reader support for Control nodes through AccessKit, described as experimental; forum users report that non-interactive nodes such as Label are not focusable by default, and that 4.7 adds an `accessibility_region` property for containers — [Godot 4.5 release page](https://godotengine.org/releases/4.5/), [Godot forum thread](https://forum.godotengine.org/t/making-control-node-focusable-by-screenreader/140244)
- Web export: Godot 4 on the web uses the Compatibility renderer (WebGL 2) only; WebGPU is not supported. Single-threaded export has been the default since 4.3. GDExtensions must be compiled for web, need "Extension Support" enabled, and need the same cross-origin isolation headers as threads. Godot 4 C# projects cannot be exported to the web — [Godot web export docs (source)](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)
- Consoles: Godot itself officially supports only Steam Deck among consoles; ports go through third parties because console SDKs are under NDA. W4 Games lists Switch, Xbox Series X|S and PlayStation 5 for Godot 4.3 and later, with Switch 2 support announced as beta in October 2025; other providers named in the docs are Pineapple Works, Lone Wolf Technology and Sickhead Games — [Godot console docs (4.5)](https://docs.godotengine.org/en/4.5/tutorials/platform/consoles.html), [W4 Consoles](https://w4games.com/w4consoles)
- Steam integration: GodotSteam (Godot 4.x, Windows/Linux/macOS) has moved from GitHub to Codeberg; the GitHub repository is archived — [GodotSteam on GitHub](https://github.com/GodotSteam/GodotSteam)

#### godot-rust (gdext)
- README states the library is "in a usable state for projects such as games, editor plugins, tools", that breaking changes occur occasionally with migration guides, and that Wasm, Android and iOS support is experimental with documentation and tooling "still lacking" — [gdext README](https://github.com/godot-rust/gdext)
- 2026 releases: typed dictionaries, non-null object APIs and Wasm builds without `api-custom` (v0.5.0); `#[func]` returning `Result` (v0.5.2); bindgen, LLVM and a C compiler no longer required, plus several use-after-free fixes (v0.5.3); typed RPCs (v0.5.4); `async fn` in `#[func(virtual)]` (v0.5.5). v0.5.3 also announces a behaviour change planned for v0.6 (editor replaces non-tool classes with placeholders) — [gdext releases](https://github.com/godot-rust/gdext/releases)
- Hot reload arrived with Godot 4.2 and needs `reloadable = true` in the `.gdextension` file; the project says hot reload is covered by its tests — [Godot forum](https://forum.godotengine.org/t/hot-reload-in-godot-instantly-see-changes-without-reloading-a-game/66089), [gdext README](https://github.com/godot-rust/gdext)
- Threading: Godot classes are deliberately `!Send` by default. The `experimental-threads` feature adds synchronisation and relaxes single-thread checks, but the crate docs warn of possible unsoundness and an unstable API; it cannot be combined with `experimental-godot-api` or with the no-threads Wasm build. Guidance is to prefer Rust threads over Godot threads — [godot crate docs](https://docs.rs/godot), [gdext issue 709](https://github.com/godot-rust/gdext/issues/709)
- The project's 2025 review named a more streamlined WebAssembly experience as a top priority for 2026 — [godot-rust 2025 review](https://godot-rust.github.io/dev/godot-rust-2025-review)

#### Bevy, bevy_ui and egui
- Bevy 0.18 (13 Jan 2026) introduced Feathers as an experimental widget library "for building tooling (such as the upcoming Bevy Editor)" and a Popover component — [Bevy 0.18 notes](https://bevy.org/news/bevy-0-18/)
- Bevy 0.19 (June 2026) introduced the rebuilt scene system (BSN, `bsn!` macro; the `.bsn` asset loader was not yet shipped) and the first upstream text entry (`EditableText`), which the source describes as a basic undecorated field with placeholder text, undo/redo and validation still unimplemented — [Bevy 0.19 notes](https://bevy.org/news/bevy-0-19/), [bevy_text 0.19 source](https://docs.rs/crate/bevy_text/0.19.0-rc.2/source/src/editing.rs)
- Bevy 0.20 (8 Oct 2026) added Feathers widgets (colour input, scrollable list view, dropdown, lazy menu) and changed BSN syntax in ways that break 0.19 `bsn!` code — [Bevy 0.20 notes](https://bevy.org/news/bevy-0-20/), [AlternativeTo](https://alternativeto.net/news/2026/10/bevy-0-20-brings-major-rendering-shading-and-ui-enhancements-to-open-source-game-engine/), [third-party upgrade blog](https://gamineai.com/blog/what-bevy-0-20-changed-before-you-upgrade-a-0-19-project-2026)
- No official Bevy Editor had shipped as of 0.20; Feathers is the toolkit intended for it — [Bevy 0.19 notes](https://bevy.org/news/bevy-0-19/), [third-party upgrade blog](https://gamineai.com/blog/what-bevy-0-20-changed-before-you-upgrade-a-0-19-project-2026)
- Shipped commercial Bevy games: Tiny Glade is the usual flagship example; one 2026 write-up says shipped commercial titles can be counted "on two hands" — [StraySpark guide](https://www.strayspark.studio/blog/bevy-rust-game-engine-2026-indie-guide), [2026 deep-dive blog](https://www.youngju.dev/blog/culture/2026-05-14-bevy-game-engine-rust-hands-on-ecs-paradigm-modern-gamedev-deep-dive-2026.en)
- egui 2026 changes relevant to dense UI: font rendering moved to `skrifa` with hinting (0.34), `harfrust` shaping for kerning and ligatures plus CSS-like classes (0.35), better mobile-web IME (0.36), colour emoji, non-Latin glyph rendering and broader AccessKit tree coverage (0.37) — [egui releases](https://github.com/emilk/egui/releases)

#### Iced and Slint
- Iced 0.14.0 added reactive rendering, time-travel debugging, first-class end-to-end testing and `table`/`grid` widgets; it is still numbered 0.x — [Iced releases](https://github.com/iced-rs/iced/releases)
- Slint's royalty-free licence covers proprietary desktop, mobile and web applications and excludes embedded; from 1.17 the listing says it is free "as long as you disclose that you use Slint" (AboutSlint widget or badge), otherwise the commercial licence applies — [Slint 1.17 licence listing](https://components.espressif.com/components/slint/slint/versions/1.17.0/license?language=en), [Slint blog, Oct 2025](https://www.slint.dev/blog/making-slint-desktop-ready)

#### Tauri and Electron with a web UI
- Tauri's stable line (2.x) uses the operating system's webview (WebView2, WKWebView, WebKitGTK). A Tauri 3 alpha exists with a separate `tauri-runtime-cef` crate (Chromium Embedded Framework) — [Tauri releases](https://github.com/tauri-apps/tauri/releases)
- The Servo-based Verso runtime for Tauri was announced in March 2025 and is reported stalled (last runtime commit October 2025); Servo's own embedding API reached crates.io with 0.4.0 in July 2026 (single third-party source) — [Tauri Verso post](https://v2.tauri.app/blog/tauri-verso-integration/), [mid-2026 webview write-up](https://www.youngju.dev/blog/2026-07-17-servo-embedding-crates-io-verso-archived.en)
- Steam overlay: Tauri issue 6196 ("Trying to make Steam Overlay work with Tauri") was closed as "not planned" in 2023; the maintainer's position is that Steam hooks OpenGL/D3D and WebView2 is closed-source. A July 2026 comment points to a community workaround (`PSG-Team/tauri-steam-overlay-surface`) reported to work on Windows 11, unverified — [Tauri issue 6196](https://github.com/tauri-apps/tauri/issues/6196)
- The Construct engine team documented the same WebView2 overlay problem; their DirectComposition workaround broke recording, Remote Play and Broadcast and was later dropped — [Construct blog](https://www.construct.net/en/blogs/ashleys-blog-2/trying-show-steam-overlay-1861)
- A developer in the WebView2 feedback forum reports the overlay works with Chromium-bundling shells (Electron, NW.js) but not Tauri on Windows — [WebView2 feedback discussion](https://github.com/MicrosoftEdge/WebView2Feedback/discussions/4019)

#### Unity and Unreal licence terms
- Unity announced the per-install Runtime Fee in September 2023 and cancelled it in September 2024, returning to seat subscriptions — [PocketGamer.biz](https://www.pocketgamer.biz/unity-cancels-infamous-runtime-fee/), [Unity pricing updates](https://unity.com/products/pricing-updates)
- Unity Pro and Enterprise rose 5% from 12 January 2026 (Pro to $2,310 per year; 2025 price was $2,200, itself up 8% from $2,040). The splash screen is optional with Unity 6 on Personal. Havok Physics is no longer included from 6.3 LTS — [80.lv](https://80.lv/articles/unity-announces-its-upcoming-2026-price-changes), [Unity pricing updates](https://unity.com/products/pricing-updates)
- A trade report describes an unannounced "Enterprise Minimum Commitment Program" causing new friction with some larger customers; not officially confirmed — [MobileGamer.biz](https://mobilegamer.biz/unity-risks-fresh-backlash-with-new-fee-demands-this-feels-like-blackmail/)
- Unreal royalties are reported and paid within 45 days of each calendar quarter — [EULA provision tracker](https://conductatlas.com/platform/unreal-engine/unreal-engine-eula/)

#### What shipped UI-heavy sims use
- Democracy 4: in-house C++ engine (Visual Studio), written by Cliff Harris and Jeff Sheen; Harris notes that every UI element normally supplied by middleware was custom coded, with Unicode text and vector rendering added by Sheen — [Wikipedia, Democracy series](https://wikipedia.com/wiki/Democracy_2), [Cliff Harris's blog, Democracy 4 category](https://positech.co.uk/cliffsblog/category/democracy-4/page/3)
- Paradox: Clausewitz (in use since 2007) plus the Jomini layer first shipped with Imperator: Rome; Paradox said "Our games are often compared to Excel, so we've completely reworked the GUI system"; Jomini cannot be retrofitted to older titles — [PCGamesN](https://pcgamesn.com/imperator-rome/paradox-new-engine-jomini)
- Football Manager 26 moved from Sports Interactive's proprietary engine to Unity and rebuilt the UI around a "Tile and Card" system; reviews call the menus a "tangled mess", and an early Steam snapshot showed "Mostly Negative" (22% of 4,930 reviews positive) — [Sports Interactive](https://www.footballmanager.com/features/total-football-total-control-fm26s-reimagined-user-interface), [Top Gear review](https://www.topgear.com/car-news/gaming/football-manager-26-review-fantastic-match-engine-tangled-mess-menus), [FinalBoss](https://finalboss.io/football-manager-26s-big-rebuild-lands-hard-on)
- Slay the Spire 2: Mega Crit abandoned more than two years of Unity work after the runtime-fee announcement and rebuilt in Godot; Early Access launched 5 March 2026 with 3 million units sold in the first week; the lead programmer said "We never hit the sort of dead ends you can hit with Unity"; Mega Crit funds Godot development — [PC Gamer](https://www.pcgamer.com/games/card-games/slay-the-spire-2-ditched-unity-for-open-source-engine-godot-after-2-years-of-development), [GamingOnLinux, sales](https://www.gamingonlinux.com/2026/03/the-godot-powered-slay-the-spire-2-has-already-hit-over-3-million-sales), [GamingOnLinux, funding](https://www.gamingonlinux.com/2026/04/godot-gets-a-funding-boost-from-slay-the-spire-2-devs-mega-crit), [AMA summary](https://slaythespire2.gg/news/mega-crit-ama-reddit-feb-2026)
- A blog case study says the Slay the Spire 2 team found Godot's UI nodes to be a weak point (weak source) — [Ziva blog](https://ziva.sh/blogs/slay-the-spire-2-godot)
- Dwarf Fortress (Steam edition): custom engine on SDL, moved to SDL2 in 2023 as the step towards ports — [GamingOnLinux](https://www.gamingonlinux.com/2023/06/dwarf-fortress-getting-close-to-a-linux-release-on-steam/page=1/)

### Inferences
- Evidence for Godot: MIT licence, a retained-mode Control tree with theming, a stable forward-compatible extension ABI, a proven 2026 commercial hit, and desktop plus Steam Deck coverage. Evidence against: no first-party charts, an experimental node-graph control, experimental screen-reader support, web export limited to WebGL 2 with extra hosting requirements for native extensions, consoles only through paid third parties, and a second-hand report that its UI nodes were a weak point for a card game far less dense than a Democracy-style screen.
- Evidence for a web shell: D3, ECharts, visx and WebGL map libraries are the most mature chart and graph tooling available anywhere, and the same UI can also run in a browser against a WebAssembly build of the core. Evidence against: Tauri 2 on Windows has an unresolved Steam overlay problem, so Electron (bundled Chromium, larger download) is the lower-risk shell for Steam; the Tauri 3 CEF runtime would remove that difference but is alpha.
- Evidence for Bevy/egui: one language end to end, no FFI boundary, and egui's 2026 text and accessibility work. Evidence against: three breaking Bevy releases in ten months of 2026, no editor, first-party text input only since June 2026, and very few shipped commercial titles. egui is immediate-mode, which suits debug and inspection tools better than a heavily styled player-facing UI (prior knowledge).
- Unity and Unreal are viable through a native plugin (P/Invoke in Unity, a third-party module in Unreal; prior knowledge), but neither offers a UI advantage for this genre, and Football Manager 26 shows that rebuilding a dense UI on a general engine is a major risk in itself rather than a shortcut.
- A custom engine (SDL3 plus Dear ImGui or a hand-built UI) is what Democracy 4 and Dwarf Fortress did; Positech's own account is that all UI widgets had to be written in-house, which is a large fixed cost for a team of one to five.
- Because the core is headless with a stable interface, the client choice is reversible at the cost of the UI layer only; the options are not mutually exclusive (for example an egui or web-based developer inspector alongside a Godot player client).

### Gaps
- Shadows of Doubt, Suzerain and Victoria 3 UI technology were not researched (search budget exhausted). Shadows of Doubt is a Unity title to the best of prior knowledge; unverified here.
- No primary postmortem was found on Godot UI performance with thousands of Control nodes, or on chart rendering cost in Godot.
- Unity versions after 6.4 (documentation URLs mention 6.6 and 6.7) and the current Unreal Engine 5.x version were not verified.
- Unreal terms come from a Meta developer page and a third-party EULA tracker, not Epic's own page (host unreachable).
- Defold licence text, raylib/MonoGame/FNA suitability for dense UI, and Electron's bundled Node version were not verified.
- Console porting prices (W4 and others) were not found.
- WebGPU availability in browsers and in Electron/Tauri webviews as of late 2026 was not verified.

---

## 2. Binding patterns between a native core and the client

### Takeaway
The tools exist to expose one Rust core to C, C++, Python, C#, JavaScript and Godot from a single definition, and to pass columnar data without copies through the Arrow C Data Interface; the constraint that shapes the design is threading, because Godot objects are not thread-safe and godot-rust's threading support is explicitly experimental, which pushes towards a core that owns its own worker thread and hands plain data snapshots to the UI thread.

### Cited Findings
- cbindgen generates C and C++11 headers from Rust; MPL-2.0; used in production by webrender, stylo and maturin; the README says development has been "largely adhoc" with no fixed release schedule — [cbindgen](https://github.com/mozilla/cbindgen)
- cxx provides safe bidirectional C++/Rust interop and positions itself against the unsafe C-style bindings produced by bindgen/cbindgen; version 1.0.204 was current in the docs.rs listing — [cxx README](https://github.com/dtolnay/cxx), [cxx on docs.rs](https://docs.rs/crate/cxx/1.0.204)
- UniFFI (Mozilla) has built-in Kotlin, Swift, Python and Ruby back ends and third-party C#, Go, C++ and others; it is used in Firefox and called production-ready but "a long way from a 1.0 release"; MPL-2.0 — [uniffi-rs](https://github.com/mozilla/uniffi-rs)
- UniFFI serialises values into byte buffers at the boundary, which is the basis of performance criticism by a newer generator, BoltFFI (0.26.1), whose "up to 1,000x faster than UniFFI" figure is self-reported — [BoltFFI docs](https://docs.rs/crate/boltffi/latest)
- Diplomat (0.17.0) uses Rust proc macros instead of an external IDL and generates C, C++, Dart, JavaScript/TypeScript, .NET (C#), Kotlin (JNA) and Python (nanobind) bindings; its JavaScript back end needs a specific Wasm C ABI setting — [Diplomat](https://github.com/rust-diplomat/diplomat)
- safer-ffi aims to reduce hand-written `unsafe` but still describes itself as alpha — [Rust users forum](https://users.rust-lang.org/t/whats-the-differences-between-cbindgen-and-safer-ffi/126162)
- Arrow C Data Interface: two small ABI-stable C structs (`ArrowSchema`, `ArrowArray`) that any project can copy into its source; designed for zero-copy sharing between runtimes in one process without depending on Arrow libraries; the producer owns the memory and the consumer calls a `release` callback; data must be treated as immutable; it is explicitly not for persistence or inter-process transfer (the IPC format covers those) — [Arrow C Data Interface spec](https://github.com/apache/arrow/blob/main/docs/source/format/CDataInterface.rst)
- In Python, the Arrow PyCapsule Interface (`__arrow_c_schema__`, `__arrow_c_array__`, `__arrow_c_stream__`) is the portable way to hand Rust-owned Arrow data to pyarrow, Polars (supported since Polars 1.3) and others without a hard dependency; `pyo3-arrow` (0.19.0) implements it for Rust extension authors — [pyo3-arrow docs](https://docs.rs/pyo3-arrow), [Polars Arrow guide](https://docs.pola.rs/user-guide/misc/arrow/), [arro3](https://github.com/kylebarron/arro3)
- Godot side: GDExtension classes built for 4.x load in later 4.y; godot-rust classes are MPL-2.0 library users; `Gd<T>` is not `Send` by default — [godot-cpp README](https://github.com/godotengine/godot-cpp), [gdext README](https://github.com/godot-rust/gdext), [gdext issue 709](https://github.com/godot-rust/gdext/issues/709)
- Factorio's model for deterministic state: scripts cannot share state across stages, each mod's runtime script runs in its own Lua instance, and anything that affects simulation must be restored identically from the save or the game desynchronises — [Factorio data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)

### Inferences
- Two layerings are both defensible. (a) Thin C ABI first (opaque handle, `create/destroy`, `submit_command(bytes)`, `step`, `query(view_id) -> buffer`, explicit `abi_version`), with every client, Python and the CLI going through it; this keeps one tested surface and makes the engine language swappable. (b) Native Rust API first, with a godot-rust extension, a PyO3 module and a C ABI as three thin adapters; this is more ergonomic per client but triples the binding surface. The cited tools support either; none of the generators removes the need to design the command/query surface by hand.
- A flat command/query design maps directly onto deterministic replay: if every state change enters through a serialisable command stamped with a turn or tick, the command log is the replay, the save can be snapshot plus trailing commands, and the same log drives golden-run tests and bug reports (design inference consistent with Factorio's practice, not a cited fact).
- Given godot-rust's threading caveats, the safer pattern is: simulation on a Rust-owned thread; the Godot extension class holds only a channel end; on `_process` the UI thread drains completed snapshots or deltas and converts them to Godot types. Godot objects are never touched off the main thread.
- For large tables (regions, cohorts, time series), Arrow record batches serve Python zero-copy. For Godot, PackedFloat32Array/PackedInt32Array/PackedByteArray are contiguous buffers and are the natural carrier, but creating one from Rust memory is normally a copy (prior knowledge, not verified this session); at one snapshot per turn in a turn-based game this copy is unlikely to matter.
- For a web UI, the equivalents are a typed-array view onto Wasm linear memory (zero-copy within the page) or Arrow IPC bytes consumed by an Arrow JavaScript library (prior knowledge).
- UniFFI-style serialise-everything generators are a poor fit for bulk columnar data but acceptable for the low-rate command and metadata surface.

### Gaps
- No source was found that measures PackedArray construction cost from a GDExtension, or documents a supported way to wrap external memory without a copy.
- Shared-memory transport between processes (for a separate core process) was not researched.
- No citable game postmortem describing an Arrow-based core/UI boundary was found; the pattern is drawn from data-tool practice.
- Versioning practice for C ABIs (symbol versioning, capability queries) was not researched beyond the Godot extension rule.

---

## 3. WebAssembly as a deployment target for the core

### Takeaway
A browser build is realistic as a secondary target: 64-bit memory and SIMD are standardised, but threads still require cross-origin isolation, Rust's threaded Wasm standard library still needs a nightly toolchain, and measured slowdowns against native range from about 10% on small kernels to 1.75–2.5x in some application benchmarks.

### Cited Findings
- WebAssembly 3.0 was completed on 17 September 2025, bundling memory64, garbage collection, exception handling and tail calls — [SD Times](https://sdtimes.com/softwaredev/wasm-3-0-standard-is-now-officially-complete/)
- Proposal status from the official tracker: Memory64 finished (working-group meeting 2025-07-23); fixed-width SIMD finished (2021); relaxed SIMD and multiple memories finished (2024-07-10); Threads still at phase 4 (not yet merged); JS Promise Integration phase 5; wide arithmetic phase 4; stack switching and custom page sizes phase 3; shared-everything threads and the Component Model at phase 1 in the W3C process — [WebAssembly proposals](https://github.com/WebAssembly/proposals), [finished proposals](https://github.com/WebAssembly/proposals/blob/main/finished-proposals.md)
- Memory64 in browsers: one 2026 roundup says Chrome and Firefox stable, Safari missing as of early 2026; another source says Wasm 3.0 features are in all three major browsers. One article says browsers cap 64-bit memories at 16 GB — [State of WebAssembly 2026](https://devnewsletter.com/p/state-of-webassembly-2026/); contradicted on Safari by [SD Times](https://sdtimes.com/softwaredev/wasm-3-0-standard-is-now-officially-complete/)
- Threads need SharedArrayBuffer, which browsers expose only to cross-origin-isolated pages (`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`) — [web.dev](https://web.dev/articles/webassembly-threads), [Godot web export docs](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)
- itch.io offers a "SharedArrayBuffer support" setting that sets the headers; Godot offers a service-worker workaround through its PWA option — [Godot 4.3 web export report](https://godotengine.org/article/progress-report-web-export-in-4-3/), [Godot web export docs](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)
- Rust + Rayon in the browser (wasm-bindgen-rayon 1.2): requires cross-origin isolation, a pinned nightly toolchain (tested with nightly-2025-11-15), `+atomics,+bulk-memory` target features and `build-std`; the README suggests shipping separate threaded and non-threaded bundles chosen by feature detection — [wasm-bindgen-rayon](https://github.com/RReverser/wasm-bindgen-rayon)
- Performance: the "Not So Fast" study argues that small scientific kernels show about a 10% slowdown but larger applications run significantly slower than native; a Node.js comparison found native modules 1.75–2.5x faster than Wasm builds of the same code — [Not So Fast summary](https://fooqux.com/article/442), [engineered.at](https://engineered.at/articles/nodejs-native-module-vs-wasm)
- godot-rust and Godot both treat web as a constrained target: gdext's Wasm support is experimental, and Godot web needs extensions compiled for web plus isolation headers — [gdext README](https://github.com/godot-rust/gdext), [Godot web export docs](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)

### Inferences
- Memory is not the limit for 10^5 to 10^6 agents: at a few hundred bytes per agent in struct-of-arrays form, 10^6 agents is a few hundred megabytes, inside the 4 GB wasm32 address space, so memory64 is not required.
- Compute is the limit. Single-threaded Wasm at roughly 1.2–2.5x native cost is acceptable for a turn-based game if a native turn takes well under a second; a model that needs all cores natively will need the threaded build, with its hosting-header and nightly-toolchain costs, or a reduced agent count on the web.
- Deterministic results between native and Wasm builds additionally depend on floating-point discipline (no fused multiply-add differences, identical maths library); this was outside this note's research and should be treated as an open risk.
- A web UI talking to a Wasm core avoids Godot's web limitations entirely, which is an argument for the web-shell client route if a browser build matters.

### Gaps
- No benchmark of an agent-based or cohort simulation in Wasm versus native at 10^5 to 10^6 agents was found.
- Safari's memory64 and threads status as of November 2026 is unresolved (conflicting secondary sources; webassembly.org feature table was unreachable).
- Whether stable Rust gained Wasm threads in `std` during 2026 was not verified; the wasm-bindgen-rayon README still documents nightly.

---

## 4. Model authoring and modding approaches

### Takeaway
Shipped games span the whole range from pure tables (Democracy) through bespoke script (Paradox) to full embedded languages (Factorio Lua, RimWorld C#, Civilization VII JavaScript); the recurring lesson is that expressiveness grows faster than tooling, so the best-regarded systems are the ones with a deterministic sandbox, staged loading, patch operations rather than file overwrites, and machine-readable schemas that power validators.

### Cited Findings

#### Democracy 3 and 4 (CSV)
- Positech: "most simulation elements are loaded from simple text or csv files"; no SDK, language or software is needed; the simulation is described as based on a neural network — [Democracy 4 modding guide](https://positech.co.uk/democracy4/modding.html)
- `simulation.csv`: each line starting with `#` defines a simulation value; a `#` column marks where inputs begin; effects link other objects into the value. `policies.csv` works the same way, with any column right of `#effects` holding an effect made of a target, value and operator terms, and an optional inertia — [Democracy 4 simulation modding](https://www.positech.co.uk/democracy4/mod_simulation.html), [Democracy 4 policy modding](https://ftp.positech.co.uk/democracy4/mod_policies.html)
- Limits reported by Positech and modders: saving a CSV in the wrong format makes it unusable; comma counts per row must match the header; inertia cannot be used on dilemma effects; forum users report difficulty changing existing vanilla values as opposed to adding new ones — [Democracy 3 policy modding](https://positech.co.uk/democracy3/modding_policies.html), [Democracy 4 dilemma modding](https://mail.positech.co.uk/democracy4/mod_dilemmas.html), [Positech forum, modifying existing](https://forums.positech.co.uk/t/modding-is-it-possible-to-mod-existing-policies-or-simulations/18845), [Positech forum, mod not working](https://forums.positech.co.uk/t/tried-to-make-a-mod-something-isnt-working-out/16215)

#### Paradox (Clausewitz/Jomini script)
- CWTools is a community library and VS Code extension that parses and validates Paradox script for "all modern Paradox Interactive games", driven by `.cwt` rule files such as `triggers.cwt` and `effects.cwt`; MIT; about 1,700 commits — [CWTools](https://github.com/cwtools/cwtools), [.cwt guidance](https://github.com/tboby/cwtools/wiki/.cwt-config-file-guidance)
- Modders argue the in-game error log is weak for finding bugs and that CWTools catches mistakes such as a trigger used in the wrong scope; logs can be flooded (one report of 9 MB in minutes from one mod) and do not always record crash causes — [Paradox forum, CWTools thread](https://forum.paradoxplaza.com/forum/threads/tool-cwtools-a-mod-validating-extension-for-vs-code.1066033/), [Paradox forum, error spam](https://admin-forum.paradoxplaza.com/forum/threads/1-11-0-1-assortment-of-error-spam-in-observer-games.1612573)
- The engine can dump its own script documentation (`script_docs`) and script profiling (`dump_script_profiling`) from the console — [Paradox forum, Jomini modding information](https://forum.paradoxplaza.com/forum/threads/grand-jomini-modding-information-manuscript.1170261/post-25391632)

#### Factorio (Lua)
- Loading is staged: settings, then a data (prototype) stage running `data.lua`, `data-updates.lua`, `data-final-fixes.lua` across all mods, after which the Lua state is discarded and prototypes are frozen; then a control stage where each mod's `control.lua` runs in its own Lua instance — [Factorio data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)
- Determinism is enforced by the sandbox: `loadfile`, `dofile`, `coroutine`, `io` and `os` are removed, `math.random` is reimplemented deterministically, and trigonometric, exponential and logarithmic functions are replaced with custom cross-platform implementations — [Factorio Lua libraries](https://lua-api.factorio.com/1.1.0/Libraries.html)
- The current Lua API documentation is versioned 2.1.9 — [Factorio data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)

#### RimWorld (XML Defs plus C#)
- PatchOperations (since Alpha 17) modify XML Defs in place by node; before that, mods overwrote whole Defs and the last in load order silently won — [RimWorld wiki, PatchOperations](https://rimworldwiki.com/wiki/Modding_Tutorials/PatchOperations)
- Harmony patches .NET methods at run time and is described as the best practice for changing game code while coexisting with other mods — [RimWorld wiki, Harmony](https://rimworldwiki.com/wiki/Modding_Tutorials/Harmony)

#### Civilization VII, Dwarf Fortress, OpenTTD
- Civilization VII scripting is JavaScript on V8 (at least two isolates), on top of an XML/SQL gameplay database and a `.modinfo` manifest; community TypeScript tooling generates mods programmatically — [CivFanatics, scripting runtime](https://forums.civfanatics.com/threads/scripting-runtime-information.695101/), [civ7-modding-tools](https://github.com/mateicanavra/civ7-modding-tools)
- Dwarf Fortress added Lua scripting in version 52.01 (21 July 2025), confined to generating procedural objects; the old raw text format still works, and vanilla raws are meant to be patched (SELECT and CUT operations) rather than edited — [Dwarf Fortress wiki, Lua scripting](https://dwarffortresswiki.org/index.php/Lua_scripting), [Bay 12 development notes](https://bay12games.com/dwarves/dev.html), [PC Gamer](https://www.pcgamer.com/games/sim/dwarf-fortress-just-made-it-easier-for-modders-to-add-their-own-procedural-creatures-items-curses-and-more-all-of-these-things-have-been-hard-coded-in-dwarf-fortress-inaccessible-to-modders-now-the-algorithms-and-data-are-available/)
- OpenTTD's NML is a Python-implemented compiler from a higher-level language to NewGRF/NFO; GPL-2.0 — [NML](https://github.com/OpenTTD/nml)

#### Embeddable languages and WebAssembly plugins
- mlua 0.12 binds Lua 5.1–5.5, LuaJIT and Luau; sandbox mode exists only for Luau; supports serde and async; MIT. The README warns it does not guarantee absolute safety and contains much `unsafe` — [mlua](https://github.com/mlua-rs/mlua)
- Luau: derived from Lua 5.1 with gradual typing; `safeenv` and `luaL_sandbox` isolate scripts and protect built-ins; MIT; used by Roblox, Alan Wake 2, Farming Simulator 2025, Second Life and Warframe — [Luau](https://github.com/luau-lang/luau), [Luau sandbox docs](https://luau.org/sandbox)
- Rhai: pure Rust; scripts cannot mutate the host unless permitted; limits on operations, stack depth and data size; custom operators and syntax for DSL use; dual MIT/Apache. It is an AST walker (stated "1 million iterations in 0.14 sec"), with an optional bytecode VM feature described as about 1.8–2x faster — [Rhai](https://github.com/rhaiscript/rhai)
- The only public cross-language benchmark found (script-bench-rs: mlua, Rhai, Rune and others) was last synchronised in October 2024 — [script-bench-rs listing](https://awesome.ecosyste.ms/projects/github.com%2Fkhvzak%2Fscript-bench-rs)
- QuickJS-ng (MIT) is the actively developed QuickJS fork; Wren is MIT with 8.2k stars, activity not determinable from the page — [quickjs-ng](https://github.com/quickjs-ng/quickjs), [Wren](https://github.com/wren-lang/wren)
- Wasmtime 50.0.1 (29 Oct 2026) is current; it exposes fuel metering and epoch interruption for bounding guest execution. WASI 0.3 was ratified on 11 June 2026 and Wasmtime 46 (22 June 2026) enabled component-model async by default — [Wasmtime releases](https://github.com/bytecodealliance/wasmtime/releases), [WASI 0.3 release page](https://wasi.dev/releases/wasi-p3), [WASI 0.3 write-up](https://jacar.es/en/wasi-preview-3-threads-and-async-in-webassembly/)
- Extism 1.41.0 (9 Oct 2026) is a plugin framework on Wasmtime 49 with host SDKs in many languages — [Extism releases](https://github.com/extism/extism/releases)
- A production precedent for Wasm-component plugins: Zed editor extensions compile Rust to `wasm32-wasip2`, though most extensions need no code at all, only a manifest — [Zed extension docs](https://github.com/zed-industries/zed/blob/main/docs/src/extensions/developing-extensions.md)

### Inferences

Comparison of authoring approaches (synthesis; ratings are judgement, grounded in the findings above and prior knowledge):

| Approach | Expressiveness | Performance | Sandboxing and determinism | Hot reload | Error reporting and tooling | Non-programmer learning curve |
|---|---|---|---|---|---|---|
| Pure tables (CSV, as Democracy) | Low: fixed column semantics, one equation per effect | Highest (compiled to arrays) | Trivial; nothing executes | Easy | Poor by default (silent format breakage reported), but spreadsheets are familiar | Lowest |
| Structured data (TOML, JSON, YAML, RON, KDL) with schema | Low to medium | Highest | Trivial | Easy | Good if a schema drives validation and editor completion | Low |
| Data plus small expression language | Medium to high for equations, conditions, table lookups | High if compiled to bytecode or closures at load | Strong: total, no I/O, deterministic by construction | Easy | Can be excellent (spans, units, dependency cycles) because the language is yours | Low to medium (spreadsheet-formula level) |
| Purpose-built DSL (Paradox-style triggers/effects/scopes) | High | Medium (interpreted; Paradox ships script profiling) | Strong | Possible | Historically weak unless invested in; Paradox's community had to build CWTools | Medium to high; scope errors are the classic pain |
| Embedded script (Lua/Luau, Rhai, JavaScript) | Very high | Medium (Luau, LuaJIT) to low (AST walkers) | Needs deliberate work: strip libraries, replace maths, per-mod states (Factorio) | Good | Mature language tooling, but game API typing is extra work | High for non-programmers |
| WebAssembly components | Very high, any language | Near native | Strongest isolation; fuel/epochs bound execution; deterministic if floats and host calls are controlled | Module swap | Toolchain burden on modders | Highest |

- The approaches layer rather than compete: Factorio and RimWorld both keep a declarative data layer that most mods never leave, and reserve code for the minority. A Democracy-like game whose content is equations, accounts, population rules and events fits "structured data plus a small expression language" for nearly all content, with an optional scripting or Wasm tier added later if demand appears.
- Three practices recur in the well-regarded systems and are cheap to adopt early: staged loading with a frozen model after load (Factorio), patch operations that target nodes instead of replacing files (RimWorld, Dwarf Fortress), and a machine-readable schema of the modding surface shipped with the game (what CWTools had to reverse-engineer for Paradox).
- An owned expression language is the only option that makes unit checking, dependency-graph extraction, documentation generation and automatic differentiation or sensitivity analysis straightforward, because the model stays a data structure rather than opaque code.
- Democracy's example effect syntax is of the form `target,constant+(coefficient*x),inertia` (prior knowledge of the shipped files; the cited pages confirm target, value/operator terms and optional inertia but the exact string was not re-read).
- Paradox script background (prior knowledge, not verified this session): content is expressed as triggers (conditions), effects (state changes), scopes (the object in context), scripted values and modifiers; common complaints are undocumented or changing script surface between patches, scope confusion, and performance of heavily scripted mods.
- Minecraft datapacks (prior knowledge, not verified this session): JSON-defined recipes, loot tables, predicates and world generation plus command "functions"; widely used but awkward for arithmetic and logic, which pushes complex mods to Java loaders.

### Gaps
- Stellaris-specific and Victoria 3-specific modding pain points, Minecraft datapacks and NML language features were not researched (search budget exhausted).
- No 2026 benchmark comparing Luau, LuaJIT, Rhai, Rune and Wasm guests on simulation-style workloads was found.
- No shipped game using WebAssembly Component Model mods was verified; Zed is an editor, and Extism's game usage was not found.
- Squirrel, Boa and Rune status were not checked. Wren's maintenance activity could not be determined.
- The Democracy 4 "overrides" mechanism for changing vanilla effects exists as a forum topic but its rules were not read.
- GDC talks on data-driven design and mod support were not retrieved.

---

## 5. Modelling languages from the simulation world

### Takeaway
There is one open interchange standard for stock-flow models, XMILE (OASIS, 2015), and a small open-source toolchain around it and Vensim's `.mdl` format (PySD, SDEverywhere, Simlin), but none is a drop-in game model format: they cover equations, stocks, flows, arrays and units, not events, discrete population rules or mod layering. They are best treated as a design reference and an import/export target.

### Cited Findings
- XMILE 1.0 is an OASIS Standard approved 14 December 2015: an XML format for sharing, interoperating and reusing system dynamics models — [XMILE 1.0](https://docs.oasis-open.org/xmile/xmile/v1.0/xmile-v1.0.html)
- PySD translates Vensim or XMILE models into Python modules to run and modify; Python 3.9 or later; MIT; community-maintained ("Maintained: Yes"); it can also emit standalone Julia with a plain ODE or a ModelingToolkit back end — [PySD repo](https://github.com/SDXorg/pysd), [PySD docs](https://pysd.readthedocs.io/en/latest/about.html)
- SDEverywhere converts Vensim (`.mdl`, including subscripts and subscript mapping) and Stella XMILE (`.stmx`) models to C, JavaScript and WebAssembly; MIT; limits include Euler integration only, no sketch conversion, no strings and no macros. Its `plugin-check` runs model checks (ranges, fit to historical data) and comparisons between model versions on every change. Used in production by Climate Interactive (En-ROADS, C-ROADS, since 2019) and Energy Innovation — [SDEverywhere](https://github.com/climateinteractive/SDEverywhere)
- XMILE support in SDEverywhere is recent: a release listing dates initial XMILE/Stella support to version 0.7.28 on 9 March 2026 — [SDEverywhere release listing](https://ost.ecosyste.ms/projects/180133/releases)
- En-ROADS is authored in Vensim and translated to WebAssembly with SDEverywhere to run in the browser; its model files are proprietary — [Climate Interactive support](https://support.climateinteractive.org/support/solutions/articles/47000888924-what-sort-of-model-is-en-roads-)
- Simlin: Apache-2.0; a Rust simulation engine compiled to WebAssembly behind a web stock-and-flow editor; imports Vensim and Stella models and exports XMILE; the repository contains `simlin-engine`, `simlin-cli`, `libsimlin`, `pysimlin`, a notebook widget and an MCP server; about 2,500 commits, 103 stars, 161 open issues; editor limits include straight-line flows only and a 10-step undo — [Simlin repo](https://github.com/bpowers/simlin), [Simlin source tree](https://github.com/bpowers/simlin/tree/main/src), [PySD complementary projects](https://pysd.readthedocs.io/en/latest/complement.html)
- A 2026 System Dynamics Society paper (OpenCLD) includes a feature comparison of open tools including Simlin, SDEverywhere and PySD — [OpenCLD paper](https://proceedings.systemdynamics.org/2026/papers/P1246.pdf)
- Unit checking: Vensim's Units Check verifies dimensional consistency equation by equation, matches units by exact name (so "Person" and "People" differ unless declared synonyms), and does not block simulation on errors — [Vensim Units Check](https://vensim.com/documentation/ref_units_check.html)
- Modelica declares units on variables to allow dimensional checking; a 2025 Modelica conference paper notes unit inference and checking are implemented inconsistently across tools — [Modelica unit inference paper](https://ecp.ep.liu.se/index.php/modelica/article/view/1287)
- ModelingToolkit.jl is at v11.46.1 (27 Oct, 2026 inferred), with a separately released ModelingToolkitBase (v1.80.0, 6 Nov) — [ModelingToolkit releases](https://github.com/SciML/ModelingToolkit.jl/releases)

### Inferences
- XMILE is the only open standard with editors (Stella, Simlin) and converters behind it, but its XML is verbose, its tool ecosystem is small (Simlin has about a hundred stars), and it has no concepts for game events, dilemmas, voter groups or mod overlays. Adopting it as the native format would trade moddability for interoperability the audience is unlikely to use.
- A stronger position is a native format designed for modders, plus an exporter to XMILE or Vensim `.mdl` for the stock-flow subset. That gives developers free use of Simlin or Vensim for diagrams and of PySD for independent re-simulation as a cross-check.
- Simlin's Rust engine and SDEverywhere's check/compare plug-ins are the closest existing analogues to "headless core plus regression tooling" and are worth reading as prior art; Simlin's licence (Apache-2.0) permits reuse.
- Concepts worth borrowing regardless of format: explicit stock/flow/auxiliary typing, subscripted (arrayed) variables for regions and cohorts, lookup tables as first-class objects, units on every variable with synonym handling, and Stan-style declared blocks (data, parameters, state, derived quantities) to separate calibration inputs from state (the Stan point is prior knowledge).
- Modelica and ModelingToolkit are acausal equation systems aimed at physical modelling and need symbolic index reduction and solvers; this is more machinery than a discrete-time policy model needs (prior knowledge). SBML is a biology-focused XML standard for reaction networks, GAMS is an algebraic optimisation modelling language, and NetLogo is an agent-based environment with its own language; none is a natural mod format for a game (prior knowledge, not verified this session).
- Spreadsheet-style formula graphs are the closest mental model to Democracy's audience: named cells, pure formulas, automatic dependency ordering. An expression language with that semantics plus stocks (state carried between turns) covers the system-dynamics core.

### Gaps
- Current release status of Modelica (specification and OpenModelica), SBML, NetLogo and GAMS was not verified (search budget exhausted).
- Whether Simlin has shipped unit checking (listed as a roadmap item in an older blog post) was not confirmed.
- ModelingToolkit's licensing after the Base split was not verified.
- No example was found of a commercial game that uses XMILE or Vensim files as its model format.

---

## 6. Tooling for the developers

### Takeaway
The Python route is mature and low-risk: PyO3 0.29 with maturin 1.16 for the module, Arrow PyCapsule export for run data, and standard notebook and dataframe tools on top; the pieces that have to be built in-house are the model-level tools (dependency graph, unit checker, documentation generator), which are straightforward only if the model is held as data.

### Cited Findings
- PyO3: 0.28 made free-threaded Python support opt-out (modules are assumed thread-safe unless marked `gil_used = true`) and enabled `abi3` on Python 3.12 and later; 0.28.2 (18 Feb 2026) fixed a soundness bug in abi3 subclassing; a changelog aggregator lists 0.29.0 on 11 June 2026 — [PyO3 free-threading guide](https://docs.rs/crate/pyo3/0.28.0/source/guide/src/free-threading.md), [PyO3 changelog aggregator](https://gitpedia.pages.dev/changelog/PyO3/pyo3)
- maturin 1.16.0 (29 Oct 2026); 1.14 added `abi3t` (free-threaded stable ABI) support for Python 3.15 with PyO3 0.29; maturin also builds UniFFI and cffi style bindings — [maturin releases](https://github.com/PyO3/maturin/releases), [PyO3 pull request 5807](https://github.com/PyO3/pyo3/pull/5807)
- Arrow export from a Rust extension: `pyo3-arrow` 0.19.0 provides zero-copy FFI through the PyCapsule interface, including a stream capsule for iterating record batches; Polars recommends library authors implement the PyCapsule interface so no hard dependency on pyarrow or Polars is needed — [pyo3-arrow docs](https://docs.rs/pyo3-arrow), [Polars Arrow guide](https://docs.pola.rs/user-guide/misc/arrow/), [Quansight on PyCapsule](https://labs.quansight.org/blog/narwhals-pycapsule)
- Compile-time units in Rust: `uom` 0.38.0 provides type-safe zero-cost dimensional analysis and supports custom systems of quantities (example `mks.rs`); MIT/Apache — [uom](https://github.com/iliekturtles/uom)
- Model-level unit checking precedent: Vensim (name-based, with synonyms, non-blocking) and Modelica (declared SI units, inconsistent tool support) — [Vensim Units Check](https://vensim.com/documentation/ref_units_check.html), [Modelica unit inference paper](https://ecp.ep.liu.se/index.php/modelica/article/view/1287)
- Model QA precedent: SDEverywhere's check and compare plug-ins run on every model change and present a browsable report of range checks and version-to-version output differences across many scenarios — [SDEverywhere](https://github.com/climateinteractive/SDEverywhere)
- Notebook integration precedent: Simlin ships a `notebook-widget` and `pysimlin` package next to its engine — [Simlin source tree](https://github.com/bpowers/simlin/tree/main/src)
- Graph editing inside the client: Godot's GraphEdit is available but experimental — [GraphEdit docs](https://docs.godotengine.org/en/latest/classes/class_graphedit.html)
- UI inspection and testing: egui 0.35 added an inspection protocol that reads the AccessKit tree of a running app, and its `kittest` harness can record video of tests (0.37); Iced 0.14 added time-travel debugging and end-to-end testing — [egui releases](https://github.com/emilk/egui/releases), [Iced releases](https://github.com/iced-rs/iced/releases)
- Paradox precedent for self-documenting script: console commands that dump script documentation and script profiling to log files — [Paradox forum, Jomini modding information](https://forum.paradoxplaza.com/forum/threads/grand-jomini-modding-information-manuscript.1170261/post-25391632)

### Inferences
- Units in a game model (currency, people, currency per person per year, percentages, index points) are user-defined at run time by mods, so compile-time crates such as `uom` help inside engine code but not for mod content; the model loader needs its own run-time dimensional checker, of the Vensim kind but ideally strict (errors block loading in developer mode).
- Run output as Arrow record batches in memory and Parquet on disk gives one path for notebooks, sweeps and CI artefacts; a CLI that takes a scenario, seed and command script and writes Parquet is the minimum harness for calibration and for golden-run tests (Parquet tooling is prior knowledge).
- Parameter sweeps and calibration can use standard Python optimisers and samplers against the PyO3 module; free-threaded Python plus a core that releases the interpreter lock allows in-process parallel sweeps, otherwise process pools are sufficient (design inference).
- Dependency graphs can be emitted as Graphviz DOT or JSON for Cytoscape or yEd directly from the loaded model; a generated reference site (every variable, its equation, units, inputs, outputs, and the mod that last changed it) is the equivalent of Paradox's `script_docs` and of what CWTools needed (Graphviz, Cytoscape and yEd capabilities are prior knowledge, not verified this session).
- An egui or web-based inspector attached to the headless core is a cheap developer tool independent of the player client choice.

### Gaps
- Graphviz, Cytoscape, yEd and Jupyter were not researched this session; statements about them are prior knowledge.
- No off-the-shelf run-time unit-checking library for user-defined expression languages in Rust was identified.
- PyO3 releases after 0.29.0 were not verified.
- cffi as an alternative Python binding route was not researched beyond maturin's support for it.

---

## 7. Testing and validation practice for simulation games

### Takeaway
The best-documented practice is Factorio's: full determinism, a large automated suite run on every commit on dedicated machines, and a "heavy mode" that saves, reloads and checksums the world every tick; the Rust ecosystem supplies the building blocks (proptest with shrinking, state-machine testing, seeded deterministic simulation harnesses), and system-dynamics tooling supplies the model-level equivalent (range checks and version comparisons across scenarios).

### Cited Findings
- Factorio heavy mode saves and reloads the game each tick and compares a CRC of the map before and after; it is very slow but "critical to help find any possible determinism issues" — [Factorio Friday Facts 315](https://factorio.com/blog/post/fff-315)
- In 2019 Wube set up dedicated machines to run tests automatically after each commit, so developers no longer had to run heavy tests locally; heavy tests took about 530 seconds on an i9-7900X — [Factorio Friday Facts 315](https://factorio.com/blog/post/fff-315)
- As early as 2014 the team stated that a determinism-breaking bug in code covered by tests would be revealed just by running the suite — [Factorio Friday Facts 60](https://factorio.com/blog/post/fff-60)
- In a March 2025 developer AMA, Factorio's CI was described as buildbot with workers on the studio's own hardware (Proxmox virtual machines and some Macs) — [Factorio developer AMA (mirror)](https://reddit.birdcat.cafe/r/factorio/comments/1jddhyg/post_space_age_developer_ama/mi9ii3u/?context=3)
- A full heavy-mode check cannot run during normal play because it would make the game unplayable — [Factorio forum](https://forums.factorio.com/viewtopic.php?p=686391)
- proptest (1.12.0): property testing with automatic shrinking; failing cases are persisted to a `proptest-regressions` directory meant to be committed; a `proptest-state-machine` crate supports transition/precondition/postcondition testing against a reference model; the project describes itself as near feature-complete and in passive maintenance — [proptest](https://github.com/proptest-rs/proptest), [state-machine testing tutorial](https://hackmd.io/@tzemanovic/B12jdEk8p)
- Deterministic simulation testing in Rust (seeded random operation sequences checked against a simple reference model after every step, with replayable seeds) was the subject of a FOSDEM 2026 talk and is described in project write-ups, which note that property tests alone miss order-dependent bugs — [FOSDEM 2026 talk transcript](https://ftp.fau.de/fosdem/2026/ub2252a/GNTZDT-rust-deterministic-simulation-testing.vtt), [usageDb testing write-up](https://usagebox.com/articles/usagedb-internals-testing-proptest-dst)
- SDEverywhere runs model checks (values within range, fit to historical data) and comparisons between two model versions over many input scenarios whenever the model changes — [SDEverywhere](https://github.com/climateinteractive/SDEverywhere)
- Paradox ships script profiling output (`dump_script_profiling`) for finding expensive script — [Paradox forum, Jomini modding information](https://forum.paradoxplaza.com/forum/threads/grand-jomini-modding-information-manuscript.1170261/post-25391632)

### Inferences
- A layered suite follows from the above: (1) golden runs: fixed scenario, seed and command script, with a state hash per turn compared against a committed baseline; (2) save/load round-trip at every turn compared by hash, which is Factorio's heavy mode and is cheap for a turn-based game; (3) property tests over random command sequences and random valid mod content asserting invariants such as sector accounts summing to zero, population conservation across cohorts, non-negative stocks and bounded indices; (4) fuzzing of the mod loader with malformed files, asserting errors rather than panics; (5) Monte Carlo batches with statistical acceptance bands on outcome distributions; (6) scripted or search-based players for balance, reporting win rates and dominant strategies; (7) sensitivity analysis over parameters.
- Model-level checks in the SDEverywhere style (declared expected ranges and historical-fit tolerances stored next to the model) let mod authors run the same checks as the developers, which doubles as mod validation.
- Thousands of headless games per CI run are practical only with the CLI/Parquet harness from section 6 and a deterministic core; golden baselines need a deliberate update procedure so that intended balance changes do not become noise.
- Snapshot-testing crates such as `insta` suit golden text and JSON outputs (prior knowledge, not verified this session).

### Gaps
- No public description was found of automated balance testing with AI players for Paradox titles, Democracy or Football Manager.
- No source specific to testing accounting identities (stock-flow consistency) in a game was found; the invariant list is drawn from economic-modelling practice.
- Fuzzing tools (cargo-fuzz and similar) and statistical testing methods were not researched this session.
- Cross-platform floating-point determinism (needed for golden runs to match across Windows, Linux and macOS) was not researched here.

---

## 8. Save/load, replay and versioning

### Takeaway
Shipped games handle model and mod change in three different ways: explicit, recorded migrations (Factorio), tolerant loading with errors when content is missing (RimWorld), or accepting that major patches break saves and offering old versions as Steam branches (Paradox). Only the first makes long-lived saves and replays reliable, and it depends on stable identifiers and a deterministic core.

### Cited Findings
- Factorio saves record the file names of migrations already applied, so each runs once. JSON migrations (prototype renames) run before Lua migrations; ordering is by mod order, then file name. Renames keep existing references valid; references to removed prototypes become invalid. The game resets recipes and technologies itself whenever mods, prototypes or start-up settings change — [Factorio migrations](https://lua-api.factorio.com/latest/auxiliary/migrations.html)
- Migrations have a cost: a 2.0.66 thread reports slow loads when a mod renames many item prototypes because migrations apply per blueprint, and staff say that cost cannot be removed — [Factorio forum](https://forums.factorio.com/viewtopic.php?p=681026)
- Removing a Factorio mod replaces its prototypes with nothing; a "fallback migrations" proposal exists with no evidence of implementation — [Factorio forum](https://forums.factorio.com/viewtopic.php?p=694050)
- Paradox: coverage of Victoria 3 update 1.15 states old saves will not carry over and mods must be updated; staff state that once a save is updated to a new patch it cannot be played on previous patches; players are directed to roll back through Steam beta branches — [Victoria 3 1.15 coverage](https://mixed-news.com/en/victoria-3-free-update-1-15-war-support-save-compatibility/), [Paradox forum, rollback thread](https://admin-forum.paradoxplaza.com/forum/threads/last-patch-1-12-1-broke-my-game-and-roll-back-to-a-previous-version-1-11-5-dont-fix-the-problem.1626218)
- Paradox games compute a checksum over game content that gates ironman/achievement eligibility; forum threads report that some content changes alter it and that debug mode changes it — [Paradox forum, checksum thread](https://admin-forum.paradoxplaza.com/forum/threads/game-checksum-displays-modified-even-with-no-mods.1565212)
- RimWorld: the wiki's guidance is that removing mods from a save is trickier than adding them; users report "remove from save" tools failing with errors — [RimWorld wiki, compatibility](https://www.rimworldwiki.com/wiki/Modding_Tutorials/Compatibility), [RimWorld wiki, troubleshooting](https://rimworldwiki.com/wiki/Modding_Troubleshooting_Tips_and_Guides)
- Godot extension binaries follow the same forward-only rule, which affects how long a shipped client can load a newer core build — [godot-cpp README](https://github.com/godotengine/godot-cpp)

### Inferences
- Snapshot saves are robust to code changes if the snapshot schema is versioned and migrated; command-log saves are tiny and give free replays but replay correctly only on the exact same core build and mod set. A common compromise is a snapshot plus the command log since the snapshot, and periodic snapshots inside replays, with the game build, model hash and ordered mod list (with versions and content hashes) stored in the header.
- A content checksum in the Paradox style is the simple way to state "this save or replay was produced by this exact model", and to gate achievements or leaderboards.
- Factorio's two-tier migrations translate directly to a model-as-data game: declarative rename maps for variable, policy and group identifiers (cheap, checkable), and scripted migrations only where state must be recomputed. Recording applied migrations in the save is the key detail.
- Stable, namespaced identifiers for every model element (for example `mod_id:variable_name`) are a precondition for both migrations and mod removal; removal policy (drop, substitute default, or refuse to load) should be decided per element type rather than left to load-time errors as in RimWorld.
- Keeping old builds available as Steam branches is a cheap fallback when a patch must break saves.

### Gaps
- Factorio's replay version rules (replays being tied to the exact game version) were not confirmed by a source this session.
- No official Paradox statement on save-compatibility policy was found; evidence is forum and press reports.
- RimWorld's internal save format and how it tolerates missing Defs was not read from a primary source.
- Democracy 3/4 save handling with changed mods was not researched.

---

## 9. Steam Workshop and mod distribution, localisation, accessibility

### Takeaway
Workshop integration is a small, well-documented API (a mod is a folder; create, update, subscribe, read install path) with Rust and Godot bindings available; localisation and accessibility for dense UIs are less settled, with Godot's screen-reader support only a year old and still experimental, and the web stack the most mature for accessibility.

### Cited Findings
- With ISteamUGC a Workshop item is a folder of files. Set-up requires configuring Steam Cloud quota (used for preview images) and enabling ISteamUGC in the app's Workshop configuration. Publishing is `CreateItem`, then `StartItemUpdate`, setters, and `SubmitItemUpdate`. Subscribed items download through the Steam client; the game reads the subscribed list and install folders and can listen for `ItemInstalled_t`. Developer metadata can be attached with `SetItemMetadata`. The user may need to accept the Workshop legal agreement — [Steamworks Workshop implementation guide](https://partner.steamgames.com/doc/features/workshop/implementation), [ISteamUGC reference](https://partner.steamgames.com/doc/api/ISteamUGC)
- Rust bindings: `steamworks` 0.13.0 targets Steamworks SDK 1.64 (master targets 1.65), exposes a `UGC` interface, dual MIT/Apache — [steamworks-rs](https://github.com/Noxime/steamworks-rs), [UGC struct docs](https://docs.rs/steamworks/0.11.0/steamworks/struct.UGC.html)
- Godot bindings: GodotSteam for Godot 4.x, now hosted on Codeberg — [GodotSteam](https://github.com/GodotSteam/GodotSteam)
- Web shells: Steamworks bindings for Electron (steamworks.js) include an overlay helper; Tauri reaches Steam through Rust-side bindings and has the overlay limitation described in section 1 — [three.js on Steam guide](https://www.summerengine.com/make-great-games/threejs-game-on-steam), [Tauri issue 6196](https://github.com/tauri-apps/tauri/issues/6196)
- Democracy 4 modders report that mods made by editing game CSVs directly could not be published through the Workshop flow, which expects the mod folder structure — [Positech forum](https://forums.positech.co.uk/t/tried-to-make-a-mod-something-isnt-working-out/16215)
- Localisation system option: Project Fluent (fluent-rs, MIT/Apache) is designed for natural-language features such as plurals, gender and conjugation — [fluent-rs](https://github.com/projectfluent/fluent-rs)
- Text rendering matters for localisation reach: Democracy 3 needed a Unicode port to support Russian and Chinese; egui only gained broader non-Latin glyph and colour emoji rendering in 0.37 (October 2026) — [Cliff Harris's blog, Democracy 4 category](https://positech.co.uk/cliffsblog/category/democracy-4/page/3), [egui releases](https://github.com/emilk/egui/releases)
- Accessibility: Godot 4.5 added AccessKit-based screen-reader support (experimental; some node types not focusable by default; 4.7 adds `accessibility_region`); egui exposes an AccessKit tree with wider coverage since 0.37 — [Godot 4.5 release page](https://godotengine.org/releases/4.5/), [Godot forum thread](https://forum.godotengine.org/t/making-control-node-focusable-by-screenreader/140244), [egui releases](https://github.com/emilk/egui/releases)

### Inferences
- If model text (names, descriptions, tooltips, event text) lives in mod folders next to the model data with stable keys, the same Workshop folder carries model, text and assets, and translation mods become ordinary mods that add only text files. Keys derived from model identifiers allow the validator to report missing translations.
- Fluent or ICU-style messages handle plurals and number formatting in generated tooltips ("+2.3% from 3 policies") better than plain key-value tables; Paradox uses YAML-like key files and Godot supports CSV and gettext PO (prior knowledge, not verified this session).
- Dense charts and node graphs are the hardest part for accessibility: screen readers need a parallel textual or tabular view of each chart, colour must not be the only channel (colour-blind-safe palettes, patterns, direct labels), UI scale and font size should be user-adjustable, and everything should be keyboard reachable. HTML/ARIA in a web shell has the deepest assistive-technology support; Godot and egui both now have a path through AccessKit but with thinner coverage (judgement based on the cited maturity statements).
- A non-Steam distribution path (plain folders, or a service such as mod.io) keeps mods working on other stores; mod.io was not researched.

### Gaps
- mod.io, Workshop moderation, mod dependency declaration and mod load-order practices were not researched (search budget exhausted).
- Localisation pipelines used by the named games (Paradox, RimWorld, Factorio) were not researched; Factorio and Paradox formats are known only from prior knowledge.
- No accessibility guidelines specific to data-dense strategy games were retrieved, and no evidence was gathered on screen-reader behaviour inside Steam Deck or Electron builds.
- Steam Deck verification requirements for text size and controller input were not researched.
