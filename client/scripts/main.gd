extends Control
## The game screen: date and time controls, headline figures, the budget, the policy
## levers, a chart and the "why" panel. Everything is generated from the model's
## catalogue and the scenario's [play] settings, so another model gives another working
## screen without changes here.

const Palette := preload("res://scripts/palette.gd")
const Format := preload("res://scripts/format.gd")
const Chart := preload("res://scripts/chart.gd")
const TracePanel := preload("res://scripts/trace_panel.gd")
const WebPanel := preload("res://scripts/web_panel.gd")
const LeverPanel := preload("res://scripts/lever_panel.gd")
const BudgetPanel := preload("res://scripts/budget_panel.gd")
const BreakdownPanel := preload("res://scripts/breakdown_panel.gd")
const PoliticsPanel := preload("res://scripts/politics_panel.gd")
const StartScreen := preload("res://scripts/start_screen.gd")

const MAX_SERIES := 4
const HELP := """[b]How to play[/b]

You run the government. Each month households work, earn, pay tax, receive benefits and spend; firms hire to meet demand; the government buys, taxes and pays benefits. Every amount is real money in the country's currency and every payment leaves one account and enters another.

[b]Change policy[/b] in the Policy panel. A change waits (shown in amber) and takes effect from the next month. Undo removes it before then. Where the country has a parliament, each change is a bill it votes on first, and a government without a majority of its own can lose one.

[b]Advance time[/b] with Next month, Next quarter or Next year. A term is five years.

[b]See why[/b]: press Why next to any figure. The panel lists what moved it last month and by how much; press an input to follow it to its own causes, and Back to return. [b]Connections[/b] shows the same figure with what it depends on and what depends on it; press a tile to move along.

[b]Who gains, who loses[/b] breaks a figure down by group (income decile, region, industry). [b]Politics[/b] shows the polls and the seats; lose office at an election and the game is over.

[b]Chart[/b] any figure over time. Dashed lines mark your policy changes. Click a name in the chart's legend to remove it.

[b]Save[/b] and [b]Load[/b] keep one saved game; a game saved with older model files still loads, and says what changed. [b]Reload model[/b] reads the model files again, so an edited formula takes effect next month without restarting; a mistake in a file is shown at the bottom and the game carries on with the old model."""

var game: PoliSim
var fmt := Format.new()
var catalogue := {}
var entries := {}  # name -> catalogue entry
var rows := {}  # row name -> catalogue entry
var play := {}
var term := 60
var scenario_path := ""
var save_path := ""
var term_announced := false
var _changes_seen := 0  # policy changes already looked at for defeated bills
var failed := false

var _date: Label
var _status: Label
var _advance: Array[Button] = []
var _save: Button
var _load: Button
var _reload: Button
var _per_year: Button
var _headline: HBoxContainer
## Stage S7.3: the model's situations (catalogue entries), and which were on when last seen.
var situations: Array = []
var _situations_on := {}
var _situation_strip: HFlowContainer
var _cards := {}  # key -> {value, change}
var budget: BudgetPanel
var breakdown: BreakdownPanel
var politics: PoliticsPanel
## Stage S5.5: the player's bloc lost office at an election; the game is over (a save can
## still be loaded).
var lost := false
var levers: LeverPanel
var chart: Chart
var trace: TracePanel
var web: WebPanel
var tabs: TabContainer
var _message: PanelContainer
var _message_text: RichTextLabel
var _dialog: AcceptDialog
## Stage S7.1: shown until a game starts, when the client starts without `--scenario`.
var start_screen: StartScreen
## True once a game has started.
var started := false


func _ready() -> void:
	theme = Palette.make_theme()
	_build_layout()
	game = PoliSim.new()
	var given := _argument("scenario", "")
	if given == "":
		_show_start_screen()
		return
	var mods := PackedStringArray()
	for name in _argument("mods", "").split(",", false):
		mods.append(find_folder(name))
	start(find_file(given), mods)


## Stage S7.1: lists the scenarios and mods, and waits for the player's choice.
func _show_start_screen() -> void:
	start_screen = StartScreen.new()
	start_screen.saves_folder = ProjectSettings.globalize_path("user://saves")
	start_screen.user_mods = ProjectSettings.globalize_path("user://mods")
	DirAccess.make_dir_recursive_absolute(start_screen.user_mods)
	add_child(start_screen)
	var base := find_folder("models").get_base_dir()
	start_screen.fill(game.scenarios(base), game.mods(PackedStringArray([find_folder("mods"), start_screen.user_mods])))
	start_screen.chosen.connect(func(path: String, mods: PackedStringArray, resume: bool) -> void:
		start_screen.queue_free()
		start_screen = null
		start(path, mods)
		if resume and started:
			_load_game())
	_set_controls(false)


## Opens a scenario with the mods chosen beyond its own, and shows its screen.
func start(path: String, mods := PackedStringArray()) -> void:
	scenario_path = path
	var error := game.open_with_mods(scenario_path, mods)
	started = error == ""
	if error != "":
		_show_message("[b]Could not start the game[/b]\n%s\n\nScenario: %s" % [error, scenario_path], true)
		_set_controls(false)
		return
	save_path = ProjectSettings.globalize_path("user://saves").path_join(game.scenario_name() + ".psave")
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	play = game.play_settings()
	term = int(play.get("term", 60))
	fmt.per_year = str(play.get("amounts", "step")) == "year"
	_per_year.set_pressed_no_signal(fmt.per_year)
	_model_changed()
	_refresh()
	var country := str(play.get("country", game.scenario_name()))
	if DisplayServer.get_name() != "headless":
		get_window().title = "PoliSim — " + country
	var notes: PackedStringArray = game.mod_notes()
	if not notes.is_empty():
		_show_message("[b]Mods[/b]: " + " ".join(notes))


static func _argument(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.substr(key.length() + 3)
	return fallback


## A folder of the game, next to the client project or inside it (as for find_file).
static func find_folder(relative: String) -> String:
	if relative.is_absolute_path():
		return relative
	var base := ProjectSettings.globalize_path("res://")
	for candidate in [base.path_join(relative), base.path_join("..").path_join(relative)]:
		if DirAccess.dir_exists_absolute(candidate):
			return candidate.simplify_path()
	return base.path_join(relative)


## Finds a file shipped next to the project (packaged build) or one level up (repository).
static func find_file(relative: String) -> String:
	if relative.is_absolute_path():
		return relative
	var base := ProjectSettings.globalize_path("res://")
	for candidate in [base.path_join(relative), base.path_join("..").path_join(relative)]:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	return base.path_join(relative)


# ---------------------------------------------------------------------------- layout

func _build_layout() -> void:
	var background := Panel.new()
	background.add_theme_stylebox_override("panel", Palette.panel_style(Palette.BG, 0, 0))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	page.add_child(top)
	_date = Label.new()
	_date.add_theme_font_size_override("font_size", Palette.TITLE)
	_date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The title gives way first when the window is narrow, so the page never overflows.
	_date.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_date.custom_minimum_size = Vector2(160, 0)
	top.add_child(_date)
	for spec in [["Next month", 1], ["Next quarter", 3], ["Next year", 12]]:
		var button := Button.new()
		button.text = spec[0]
		button.name = "advance_%d" % spec[1]
		var count: int = spec[1]
		button.pressed.connect(func() -> void: advance(count))
		top.add_child(button)
		_advance.append(button)
	top.add_child(VSeparator.new())
	_per_year = _tool_button(top, "Amounts a year", func() -> void: show_per_year(_per_year.button_pressed))
	_per_year.toggle_mode = true
	_per_year.name = "per_year"
	_per_year.tooltip_text = "Show amounts paid each month at an annual rate (twelve times the month), as published accounts and budgets are."
	_save = _tool_button(top, "Save", func() -> void: _save_game())
	_load = _tool_button(top, "Load", func() -> void: _load_game())
	_reload = _tool_button(top, "Reload model", func() -> void: _reload_model())
	_tool_button(top, "Help", func() -> void: _show_dialog("PoliSim", HELP))
	_status = Label.new()
	_status.add_theme_color_override("font_color", Palette.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)

	_headline = HBoxContainer.new()
	_headline.add_theme_constant_override("separation", 12)
	page.add_child(_headline)
	_situation_strip = HFlowContainer.new()
	_situation_strip.name = "situations"
	_situation_strip.add_theme_constant_override("h_separation", 8)
	_situation_strip.add_theme_constant_override("v_separation", 6)
	_situation_strip.visible = false
	page.add_child(_situation_strip)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	page.add_child(split)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(735, 0)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left_scroll.add_child(left)
	budget = BudgetPanel.new()
	budget.fmt = fmt
	budget.chart_requested.connect(func(row: String, _label: String) -> void: add_to_chart(row))
	budget.explain_requested.connect(func(name: String) -> void: explain(name, true))
	left.add_child(budget)
	breakdown = BreakdownPanel.new()
	breakdown.fmt = fmt
	left.add_child(breakdown)
	politics = PoliticsPanel.new()
	politics.fmt = fmt
	left.add_child(politics)
	levers = LeverPanel.new()
	levers.fmt = fmt
	levers.lever_changed.connect(_lever_typed)
	levers.lever_cancelled.connect(func(name: String) -> void:
		game.cancel_lever(name)
		_refresh())
	left.add_child(levers)

	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	chart = Chart.new()
	chart.fmt = fmt
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(420, 300)
	chart.series_removed.connect(func(row: String) -> void:
		chart.series = chart.series.filter(func(s): return s["row"] != row)
		_refresh_chart())
	right.add_child(chart)
	trace = TracePanel.new()
	trace.fmt = fmt
	trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trace.custom_minimum_size = Vector2(420, 300)
	trace.follow.connect(func(name: String) -> void: explain(name, true))
	trace.back.connect(_trace_back)
	trace.chart.connect(func(row: String) -> void: add_to_chart(row))
	# "Why did it change?" and the icon web (stage S6.1) share the lower right.
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(420, 300)
	right.add_child(tabs)
	tabs.add_child(trace)
	tabs.set_tab_title(0, "Why did it change?")
	web = WebPanel.new()
	web.fmt = fmt
	web.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(web)
	tabs.set_tab_title(1, "Connections")

	_message = PanelContainer.new()
	_message.add_theme_stylebox_override("panel", Palette.panel_style(Palette.PANEL_RAISED))
	_message.visible = false
	page.add_child(_message)
	var message_row := HBoxContainer.new()
	_message.add_child(message_row)
	_message_text = RichTextLabel.new()
	_message_text.bbcode_enabled = true
	_message_text.fit_content = true
	_message_text.scroll_active = false
	_message_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_text.selection_enabled = true
	message_row.add_child(_message_text)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _message.visible = false)
	message_row.add_child(close)


func _tool_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Rebuilds everything that depends on the model: after opening, loading or reloading.
func _model_changed() -> void:
	catalogue = game.catalogue()
	fmt.configure(catalogue, play)
	entries.clear()
	rows.clear()
	var lever_entries := []
	for entry in catalogue.get("entries", []):
		entries[entry["name"]] = entry
		if str(entry["row"]) != "":
			rows[entry["row"]] = entry
		if entry["kind"] == "lever" and entry.get("player", true):
			lever_entries.append(entry)
	trace.entries = entries
	web.build(entries)
	budget.build(catalogue, entries, str(play.get("government", "government")))
	breakdown.build(play, entries)
	politics.build(play)
	levers.build(lever_entries)
	levers.set_legislature(bool(catalogue.get("legislature", false)))
	_build_headline()
	# Stage S7.3: the situations, as they stand now (nothing is announced for a game just
	# opened, loaded or reloaded).
	situations.clear()
	_situations_on.clear()
	for entry in catalogue.get("entries", []):
		if str(entry.get("situation", "")) != "":
			situations.append(entry)
			_situations_on[entry["name"]] = game.latest(str(entry["row"])) == true


func _headline_keys() -> Array:
	var keys: Array = play.get("headline", [])
	if keys.is_empty():
		keys = play.get("watch", [])
	return keys.slice(0, 6)


## A headline key is a row name, optionally with "-" in front to show it negated.
func _key_entry(key: String) -> Dictionary:
	return rows.get(key.trim_prefix("-"), {})


func _key_label(key: String) -> String:
	var labels: Dictionary = play.get("labels", {})
	if labels.has(key):
		return str(labels[key])
	return str(_key_entry(key).get("label", key))


func _build_headline() -> void:
	for child in _headline.get_children():
		child.queue_free()
	_cards.clear()
	for key in _headline_keys():
		var entry := _key_entry(key)
		if entry.is_empty():
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = str(entry.get("doc", ""))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		var label := Label.new()
		label.text = _key_label(key)
		label.add_theme_color_override("font_color", Palette.MUTED)
		label.add_theme_font_size_override("font_size", Palette.SMALL)
		box.add_child(label)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", Palette.FIGURE)
		box.add_child(value)
		var line := HBoxContainer.new()
		box.add_child(line)
		var change := Label.new()
		change.add_theme_font_size_override("font_size", Palette.SMALL)
		change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		change.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		change.custom_minimum_size = Vector2(60, 0)
		line.add_child(change)
		var name: String = entry["name"]
		var plot := Button.new()
		plot.text = "Chart"
		plot.pressed.connect(func() -> void: add_to_chart(key))
		line.add_child(plot)
		var why := Button.new()
		why.text = "Why"
		why.pressed.connect(func() -> void: explain(name, true))
		line.add_child(why)
		_headline.add_child(card)
		_cards[key] = {"value": value, "change": change}


# ---------------------------------------------------------------------------- reading

func latest_value(key: String) -> Variant:
	var v: Variant = game.latest(key.trim_prefix("-"))
	return _negated(key, v)


func previous_value(key: String) -> Variant:
	var v: Variant = game.previous(key.trim_prefix("-"))
	return _negated(key, v)


static func _negated(key: String, v: Variant) -> Variant:
	if v == null or not key.begins_with("-"):
		return v
	return -v


func _refresh() -> void:
	var done := game.steps_done()
	_show_situations()
	if done == 0:
		_date.text = "%s · start of term, %s" % [str(play.get("country", "")), fmt.month_name(0)]
	else:
		_date.text = "%s · %s · month %d of %d" % [str(play.get("country", "")), fmt.month_name(done - 1), done, term]
	var modded := PackedStringArray()
	for mod in game.active_mods():
		modded.append(str(mod["name"]))
	if not modded.is_empty():
		_date.text += " · with " + ", ".join(modded)
	for key in _cards:
		var entry := _key_entry(key)
		var card: Dictionary = _cards[key]
		var now: Variant = latest_value(key)
		var before: Variant = previous_value(key)
		card["value"].text = fmt.value(entry, now, true, false)
		if now != null and before != null:
			card["change"].text = fmt.change(entry, now - before) + " on last month"
		else:
			card["change"].text = "no change yet"
		card["change"].add_theme_color_override("font_color", Palette.MUTED)
	budget.refresh(func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	breakdown.refresh(func(name: String) -> Dictionary: return game.cells(name),
		func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	politics.refresh(func(name: String) -> Dictionary: return game.cells(name),
		func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row),
		game.steps_done())
	levers.refresh(func(name: String) -> Variant: return game.latest(name), game.pending())
	web.refresh(func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	_refresh_chart()
	_set_controls(not failed and not lost)


func _refresh_chart() -> void:
	var steps := game.history_steps()
	var markers := []
	for c in game.changes():
		if not c.get("passed", true):
			continue  # voted down: it never took effect
		var entry: Dictionary = entries.get(c["lever"], {})
		markers.append({"step": c["step"], "text": "%s → %s" % [entry.get("label", c["lever"]), fmt.value(entry, c["value"], false, false)]})
	var k: float = fmt.factor(chart.entry) if not chart.series.is_empty() else 1.0
	for s in chart.series:
		var values := game.series(str(s["row"]).trim_prefix("-"))
		var sign := -1.0 if s["row"].begins_with("-") else 1.0
		if sign * k != 1.0:
			for i in values.size():
				values[i] = values[i] * sign * k
		s["values"] = values
	chart.set_data(steps, markers)


func _set_controls(enabled: bool) -> void:
	var busy := game != null and game.is_busy()
	for button in _advance:
		button.disabled = not enabled or busy
	_save.disabled = not enabled or busy
	_reload.disabled = busy or game == null
	_load.disabled = busy or game == null or not FileAccess.file_exists(save_path)
	_status.text = "working…" if busy else ""


# ---------------------------------------------------------------------------- actions

## Shows flows at an annual rate, or per step.
func show_per_year(on: bool) -> void:
	fmt.per_year = on
	_per_year.set_pressed_no_signal(on)
	if game != null and catalogue.size() > 0:
		_model_changed()
		_refresh()
		if not trace.trail.is_empty():
			explain(trace.trail[trace.trail.size() - 1], false)


func advance(months: int) -> void:
	if failed or lost or game.is_busy():
		return
	game.advance(months)
	_set_controls(true)


func _lever_typed(name: String, raw: String) -> void:
	var refused := game.set_lever(name, raw)
	if refused != "":
		_show_message("[b]%s was not changed[/b]: %s" % [entries.get(name, {}).get("label", name), refused], true)
	_refresh()


func add_to_chart(key: String) -> void:
	var entry := _key_entry(key)
	if entry.is_empty() or chart.has_row(key):
		return
	var unit := [entry.get("shown_unit", ""), fmt.is_money(entry), fmt.is_rate(entry)]
	if not chart.series.is_empty():
		var first := chart.entry
		if [first.get("shown_unit", ""), fmt.is_money(first), fmt.is_rate(first)] != unit:
			chart.series.clear()
			_status.text = "chart cleared: different unit"
	if chart.series.is_empty():
		chart.entry = entry
	if chart.series.size() >= MAX_SERIES:
		chart.series.pop_front()
	var color: Color = Palette.SERIES[0]
	var used := chart.series.map(func(s): return s["color"])
	for c in Palette.SERIES:
		if not used.has(c):
			color = c
			break
	chart.series.append({"row": key, "label": _key_label(key), "values": PackedFloat64Array(), "color": color})
	_refresh_chart()


func explain(name: String, push: bool) -> void:
	if push:
		if trace.trail.is_empty() or trace.trail[trace.trail.size() - 1] != name:
			trace.trail.append(name)
	trace.show_waiting(name)
	game.request_explanation(name)
	web.show_value(name)


func _trace_back() -> void:
	if trace.trail.size() > 1:
		trace.trail.remove_at(trace.trail.size() - 1)
		explain(trace.trail[trace.trail.size() - 1], false)


func _save_game() -> void:
	game.save_game(save_path)
	_set_controls(true)


func _load_game() -> void:
	game.load_game(save_path)
	_set_controls(true)


func _reload_model() -> void:
	game.reload_model()
	_set_controls(true)


## Stage S7.0: what loading a save made with other model files did, in the player's words.
func _migration_note(event: Dictionary) -> String:
	var label := func(name: String) -> String:
		var entry: Dictionary = entries.get(name, {})
		return str(entry.get("label", name)) if str(entry.get("label", "")) != "" else name.replace("_", " ")
	var lines := PackedStringArray(["[b]This game was saved with an earlier version of the model.[/b] It carries on with the current one: %d values carried over." % int(event["carried"])])
	var reset := PackedStringArray()
	for name in event["reset"]:
		reset.append(label.call(name))
	if not reset.is_empty():
		lines.append("New or changed, starting from their initial values: " + ", ".join(reset) + ".")
	var clamped := PackedStringArray()
	for name in event["clamped"]:
		clamped.append(label.call(name))
	if not clamped.is_empty():
		lines.append("Policies outside their new limits, moved to the nearest limit: " + ", ".join(clamped) + ".")
	var renamed := PackedStringArray()
	for pair in event["renamed"]:
		var parts := str(pair).split("\t")
		renamed.append("%s (was %s)" % [label.call(parts[1]), parts[0].replace("_", " ")])
	if not renamed.is_empty():
		lines.append("Renamed: " + ", ".join(renamed) + ".")
	var dropped: PackedStringArray = event["dropped"]
	if not dropped.is_empty():
		lines.append("No longer in the model: " + ", ".join(Array(dropped).map(func(n): return str(n).replace("_", " "))) + ".")
	return "\n".join(lines)


func _show_message(bbcode: String, problem := false) -> void:
	_message_text.text = bbcode
	_message.add_theme_stylebox_override("panel", Palette.panel_style(Palette.BAD.darkened(0.6) if problem else Palette.PANEL_RAISED))
	_message.visible = true


func _show_dialog(title: String, bbcode: String) -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = AcceptDialog.new()
	_dialog.title = title
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = bbcode
	text.fit_content = true
	text.custom_minimum_size = Vector2(620, 0)
	_dialog.add_child(text)
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(680, 0))


func _announce_term() -> void:
	term_announced = true
	var lines := PackedStringArray(["[b]Your %d-month term is over.[/b]\n" % term])
	lines.append("[table=3][cell][b]Figure[/b]   [/cell][cell][b]First month[/b]   [/cell][cell][b]Last month[/b][/cell]")
	for key in _headline_keys():
		var entry := _key_entry(key)
		var values := game.series(key.trim_prefix("-"))
		if entry.is_empty() or values.is_empty():
			continue
		var sign := -1.0 if key.begins_with("-") else 1.0
		var first: Variant = values[0] * sign
		var last: Variant = values[values.size() - 1] * sign
		if entry.get("type", "") == "int":
			first = int(first)
			last = int(last)
		lines.append("[cell]%s   [/cell][cell]%s   [/cell][cell]%s[/cell]" % [_key_label(key), fmt.value(entry, first), fmt.value(entry, last)])
	lines.append("[/table]\n")
	var passed := game.changes().filter(func(c): return c.get("passed", true)).size()
	lines.append("You changed policy %d times. You can keep governing, or load your save to try again." % passed)
	_show_dialog("End of term", "\n".join(lines))


# ---------------------------------------------------------------------------- events

## Stage S5.5: true once the player's bloc is out of government.
func _player_lost() -> bool:
	var name := str(play.get("politics", {}).get("player", ""))
	return name != "" and game.latest(name) == false


## Stage S5.5: election night. The results, and the end of the game if the player lost.
func _announce_election() -> void:
	var settings: Dictionary = play.get("politics", {})
	if settings.is_empty() or game.latest(str(settings.get("election", ""))) != true:
		return
	lost = _player_lost()
	_show_dialog("Election night" if not lost else "Election night: you have lost office",
		politics.election_report(func(name: String) -> Dictionary: return game.cells(name), not lost))


## Stage S7.3: the situations in force, under the headline, each with the month it began.
func _show_situations() -> void:
	for child in _situation_strip.get_children():
		_situation_strip.remove_child(child)
		child.queue_free()
	for entry in situations:
		var row := str(entry["row"])
		if game.latest(row) != true:
			continue
		var chip := PanelContainer.new()
		chip.name = "situation_" + str(entry["name"])
		var good := str(entry["situation"]) == "good"
		var style := Palette.panel_style(Palette.PANEL_RAISED, 4, 6)
		style.border_color = Palette.GOOD if good else Palette.BAD
		style.set_border_width_all(2)
		chip.add_theme_stylebox_override("panel", style)
		chip.tooltip_text = str(entry.get("doc", ""))
		var label := Label.new()
		label.text = str(entry.get("label", entry["name"]))
		var since := situation_onset(row)
		if since >= 0:
			label.text += " · since " + fmt.month_name(since)
		label.add_theme_color_override("font_color", Palette.GOOD if good else Palette.BAD)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(label)
		_situation_strip.add_child(chip)
	_situation_strip.visible = _situation_strip.get_child_count() > 0


## The step a situation that is on now last came on, from the history; -1 if unknown.
func situation_onset(row: String) -> int:
	var values: PackedFloat64Array = game.series(row)
	var steps: PackedInt64Array = game.history_steps()
	if values.is_empty() or values.size() != steps.size():
		return -1
	var i := values.size() - 1
	while i > 0 and values[i - 1] >= 0.5:
		i -= 1
	return int(steps[i])


## Stage S7.3: tells the player which situations began or ended since the last step.
func _announce_situations() -> void:
	var lines := PackedStringArray()
	for entry in situations:
		var name := str(entry["name"])
		var now: bool = game.latest(str(entry["row"])) == true
		var was: bool = _situations_on.get(name, false)
		_situations_on[name] = now
		var label := str(entry.get("label", name))
		if now and not was:
			var doc := str(entry.get("doc", ""))
			lines.append("[b]%s[/b]%s" % [label, (": " + doc + ".") if doc != "" else "."])
		elif was and not now:
			lines.append("[b]%s[/b] is over." % label)
	if lines.is_empty():
		return
	var note := "\n".join(lines)
	if _message.visible:
		_message_text.text += "\n" + note
	else:
		_show_message(note)


## Stage S5.4: says which bills the House of Commons voted down since the last message.
func _announce_votes() -> void:
	var changes := game.changes()
	var lines := PackedStringArray()
	for i in range(_changes_seen, changes.size()):
		var c: Dictionary = changes[i]
		if c.get("passed", true):
			continue
		var entry: Dictionary = entries.get(c["lever"], {})
		lines.append("%s to %s, in %s: %d for, %d against" % [entry.get("label", c["lever"]),
			fmt.value(entry, c["value"], false, true), fmt.month_name(int(c["step"])),
			int(c["votes_for"]), int(c["seats"]) - int(c["votes_for"])])
	_changes_seen = changes.size()
	if not lines.is_empty():
		_show_message("[b]The House of Commons voted down %s[/b]\n%s\nYour government lacks a majority of its own; its partners and the opposition vote by their side of politics." % [
			"a bill" if lines.size() == 1 else "%d bills" % lines.size(), "\n".join(lines)])


func _process(_delta: float) -> void:
	if game == null or not started:
		return
	var events := game.poll()
	for event in events:
		match str(event["kind"]):
			"stepped":
				_announce_votes()
				_announce_situations()
				_announce_election()
				if game.steps_done() >= term and not term_announced:
					_announce_term.call_deferred()
			"failed":
				failed = true
				_show_message("[b]The simulation stopped[/b]\n%s\n\nLoad your save, or reload a corrected model." % event["error"], true)
			"explained":
				if event.has("explanation"):
					trace.show_explanation(event["explanation"])
				else:
					trace.show_error(event["name"], event["error"])
			"saved":
				if event["error"] != "":
					_show_message("[b]Could not save[/b]: " + event["error"], true)
				else:
					_status.text = "saved"
			"loaded":
				if event["error"] != "":
					_show_message("[b]Could not load[/b]: " + event["error"], true)
				else:
					failed = false
					term_announced = game.steps_done() >= term
					_changes_seen = game.changes().size()
					lost = _player_lost()
					trace.trail.clear()
					_model_changed()
					_status.text = "loaded"
					var note := ""
					var missing: PackedStringArray = event.get("missing_mods", PackedStringArray())
					if not missing.is_empty():
						note = "[b]Mods this game was played with are missing[/b] and were left out: %s.\n" % ", ".join(missing)
					if event.get("migrated", false):
						note += _migration_note(event)
					if note != "":
						_show_message(note)
			"reloaded":
				if event["error"] != "":
					_show_message("[b]The model files have a problem; the game carries on with the previous model.[/b]\n[code]%s[/code]" % event["error"], true)
				else:
					failed = false
					_model_changed()
					var reset: PackedStringArray = event["reset"]
					var note := "Model reloaded: changes take effect from next month."
					if not reset.is_empty():
						note += " These started again from their initial values: " + ", ".join(reset)
					_show_message(note)
	if not events.is_empty():
		_refresh()
	elif _status.text == "working…" and not game.is_busy():
		_set_controls(not failed and not lost)
