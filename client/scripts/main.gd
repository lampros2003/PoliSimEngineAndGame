extends Control
## The game screen (stage S13.2): a slim top bar over the board, the cause-and-effect graph
## that is the main way to play. Every node, every figure on the top bar and every budget
## line opens one popup that grows from it; the Budget and Parliament are sheets laid over
## the board. Everything is generated from the model's catalogue and the scenario's [play]
## settings, so another model gives another working screen without changes here.
##
## For tests and tests/look.gd, a small stable set of methods drives the screen as a player
## would: open_node(key), open_indicator(name), open_overlay(name), close_overlay(),
## close_popup(), type_lever(lever, value), hover(key), menu_action(name), advance(months),
## answer_dilemma(name, answer); and reads it: popup_kind(), policy_card(),
## indicator_card(), current_trace(), notice_text(), capital_text(), title_text(),
## flag_text(key), dilemma_title(), can_advance(), board_levers().

const Palette := preload("res://scripts/palette.gd")
const Format := preload("res://scripts/format.gd")
const Web := preload("res://scripts/web.gd")
const PopupCard := preload("res://scripts/popup.gd")
const Sheet := preload("res://scripts/sheet.gd")
const LeverPanel := preload("res://scripts/lever_panel.gd")
const IndicatorCard := preload("res://scripts/indicator_card.gd")
const GroupCard := preload("res://scripts/group_card.gd")
const BudgetPanel := preload("res://scripts/budget_panel.gd")
const PoliticsPanel := preload("res://scripts/politics_panel.gd")
const StartScreen := preload("res://scripts/start_screen.gd")

const SETTINGS := "user://settings.cfg"
const BAR_HEIGHT := 64.0
const HELP := """[b]The board[/b] is the country. Round the rim are your [b]policies[/b] (discs), grouped by area; inside them the [b]indicators[/b] they move (rings); at the centre the government's approval, the months to the election and its political capital. A bigger node matters more. Point at anything to see what it is linked to: arrows run from cause to effect, blue where the effect rises and brick where it falls, thicker for a stronger effect. Drag to move the board, turn the wheel to zoom, Home to see it all.

[b]Change policy[/b] by clicking a policy: set it with the slider or type the exact figure. A change waits (ochre) and takes effect from next month; Undo removes it before then. Each change is a bill: it costs political capital, and a government without a majority of its own can lose the vote.

[b]See why[/b]: click an indicator for its history, what moved it last month (click a cause to follow it, Back to return), who gains and who loses, and the policies that move it most.

[b]Advance time[/b] with Next month, Quarter or Year. When a question is put to you, answer it: no month runs until you do. Flags under the centre show the situations in force and your answers.

[b]The Budget[/b] and [b]Parliament[/b] open from the top bar (Parliament also from the centre). The menu saves and loads your game, reloads the model files, shows amounts a year or a month, and sets the size of the screen.

[color=#55606c]Pictograms from game-icons.net by Lorc, Delapouite and others, CC BY 3.0 (client/icons/CREDITS.md). Type: Jost and IBM Plex Sans, SIL Open Font License.[/color]"""

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
## Stage S5.5: the player's bloc lost office at an election; the game is over (a save can
## still be loaded).
var lost := false
## Stage S7.3: the model's situations (catalogue entries), and which were on when last seen.
var situations: Array = []
var _situations_on := {}
## Stage S9.1: the model's dilemmas, and the sheet that asks for an answer to one of them.
var dilemmas: Array = []
var dilemma_dialog: Control
var _dilemma_asked := ""
## Stage S12.5: each waiting change's cost in political capital.
var _costs := {}
var _capital_text := ""
## Stage S7.1: shown until a game starts, when the client starts without `--scenario`.
var start_screen: StartScreen
## True once a game has started.
var started := false

var board: Web
var popup: PopupCard
var budget: BudgetPanel
var politics: PoliticsPanel
var _budget_sheet: Sheet
var _parliament_sheet: Sheet
var _dialog: Sheet
var _sheets: Control
var _bar: PanelContainer
var _date: Label
var _country: Label
var _chips: HBoxContainer
var _chip := {}  # key -> {button, value, change, entry, shown}
var _capital: Button
var _advance: Array[Button] = []
var _menu: MenuButton
var _parliament_button: Button
## Top-bar buttons that drop their words on a narrow window, keeping their pictograms.
var _wide: Array[Button] = []
var _status: Label
var _message: PanelContainer
var _message_text: RichTextLabel
var _forecast_timer: Timer
var _effects_timer: Timer
var _scale_choice := 0.0  # 0 for automatic


func _ready() -> void:
	theme = Palette.make_theme()
	_apply_scale(_saved_scale())
	_build_layout()
	game = PoliSim.new()
	var given := _argument("scenario", "")
	if given == "":
		_show_start_screen()
		return
	var mods := PackedStringArray()
	for name in _argument("mods", "").split(",", false):
		mods.append(find_folder(name))
	start(find_file(given), mods, _argument("language", ""))


## Stage S7.1: lists the scenarios and mods, and waits for the player's choice.
func _show_start_screen() -> void:
	start_screen = StartScreen.new()
	start_screen.saves_folder = ProjectSettings.globalize_path("user://saves")
	start_screen.user_mods = ProjectSettings.globalize_path("user://mods")
	DirAccess.make_dir_recursive_absolute(start_screen.user_mods)
	add_child(start_screen)
	var base := find_folder("models").get_base_dir()
	start_screen.fill(game.scenarios(base), game.mods(PackedStringArray([find_folder("mods"), start_screen.user_mods])))
	start_screen.chosen.connect(func(path: String, mods: PackedStringArray, resume: bool, language: String) -> void:
		start_screen.queue_free()
		start_screen = null
		start(path, mods, language)
		if resume and started:
			load_game())
	_set_controls(false)


## Opens a scenario with the mods chosen beyond its own, in a language from the model's
## text ("" for its own words), and shows its board.
func start(path: String, mods := PackedStringArray(), language := "") -> void:
	scenario_path = path
	close_popup()
	var error := game.open_game(scenario_path, mods, language)
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
	_model_changed()
	_refresh()
	var country := str(play.get("country", game.scenario_name()))
	if DisplayServer.get_name() != "headless":
		get_window().title = "PoliSim — " + country
	var notes: PackedStringArray = game.mod_notes()
	if not notes.is_empty():
		_show_message("[b]Mods[/b]: " + " ".join(notes))
	_want_effects()


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


# ---------------------------------------------------------------------------- scale

## The UI scale: the player's choice from the menu, or automatic from the window's height
## (a 1440-pixel-high screen gets 1.5), kept in user://settings.cfg.
func _saved_scale() -> float:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		_scale_choice = float(config.get_value("ui", "scale", 0.0))
	return _scale_choice


func _apply_scale(choice: float) -> void:
	_scale_choice = choice
	if DisplayServer.get_name() == "headless":
		return
	var factor := choice
	if factor <= 0.0:
		var height := float(DisplayServer.window_get_size().y)
		factor = clampf(snappedf(height / 960.0, 0.25), 1.0, 2.0)
	get_window().content_scale_factor = factor


func set_ui_scale(choice: float) -> void:
	_apply_scale(choice)
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("ui", "scale", choice)
	config.save(SETTINGS)
	_update_menu()


# ---------------------------------------------------------------------------- layout

func _build_layout() -> void:
	add_child(Palette.paper())
	board = Web.new()
	board.fmt = fmt
	board.name = "board"
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_top = BAR_HEIGHT
	board.node_pressed.connect(func(key: String) -> void: open_node(key))
	add_child(board)
	_build_bar()
	# A notice at the lower left: bills voted down, situations, mods, problems.
	_message = PanelContainer.new()
	_message.name = "notice"
	_message.visible = false
	_message.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_message.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message.offset_left = 20
	_message.offset_bottom = -20
	_message.custom_minimum_size = Vector2(500, 0)
	add_child(_message)
	var message_row := VBoxContainer.new()
	message_row.add_theme_constant_override("separation", 6)
	_message.add_child(message_row)
	_message_text = RichTextLabel.new()
	_message_text.bbcode_enabled = true
	_message_text.fit_content = true
	_message_text.scroll_active = false
	_message_text.custom_minimum_size = Vector2(460, 0)
	_message_text.selection_enabled = true
	message_row.add_child(_message_text)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = "Link"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: _message.visible = false)
	message_row.add_child(close)
	_sheets = Control.new()
	_sheets.name = "sheets"
	_sheets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_sheets)
	budget = BudgetPanel.new()
	budget.fmt = fmt
	budget.line_pressed.connect(func(name: String, origin: Rect2) -> void:
		var entry: Dictionary = entries.get(name, {})
		open_indicator(name, str(entry.get("row", name)), origin))
	_budget_sheet = _new_sheet("The Budget", 900.0)
	_budget_sheet.body.add_child(budget)
	politics = PoliticsPanel.new()
	politics.fmt = fmt
	politics.group_pressed.connect(open_node)
	_parliament_sheet = _new_sheet("Parliament", 900.0)
	_parliament_sheet.body.add_child(politics)
	popup = PopupCard.new()
	popup.name = "popup"
	popup.top_margin = BAR_HEIGHT
	add_child(popup)
	popup.closed.connect(func() -> void:
		board.select("")
		_update_input())
	_forecast_timer = Timer.new()
	_forecast_timer.one_shot = true
	_forecast_timer.wait_time = 0.3
	_forecast_timer.timeout.connect(_request_forecast)
	add_child(_forecast_timer)
	# The effects table is asked for once the screen has been idle a moment after a month.
	_effects_timer = Timer.new()
	_effects_timer.one_shot = true
	_effects_timer.wait_time = 1.5
	_effects_timer.timeout.connect(_request_effects)
	add_child(_effects_timer)


func _new_sheet(title: String, width: float) -> Sheet:
	var sheet := Sheet.new(title, width)
	sheet.top_margin = BAR_HEIGHT
	sheet.visible = false
	_sheets.add_child(sheet)
	sheet.closed.connect(_update_input)
	return sheet


## The top bar: country and month; the headline figures as chips; the one primary action,
## Next month, with a quarter and a year; the Budget, Parliament and the menu.
func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.name = "top_bar"
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	var band := StyleBoxFlat.new()
	band.bg_color = Palette.CARD_DEEP
	band.border_color = Palette.INK
	band.border_width_bottom = 3
	band.content_margin_left = 18
	band.content_margin_right = 10
	band.content_margin_top = 6
	band.content_margin_bottom = 8
	_bar.add_theme_stylebox_override("panel", band)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	var where := VBoxContainer.new()
	where.add_theme_constant_override("separation", -4)
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(where)
	_country = Label.new()
	_country.theme_type_variation = "Heading"
	_country.add_theme_color_override("font_color", Palette.INK)
	_country.mouse_filter = Control.MOUSE_FILTER_PASS
	where.add_child(_country)
	_date = Label.new()
	_date.name = "date"
	_date.add_theme_font_override("font", Palette.display(500))
	_date.add_theme_font_size_override("font_size", 21)
	where.add_child(_date)
	row.add_child(_rule())
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 0)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.clip_contents = true
	row.add_child(_chips)
	# Stage S12.5: the government's political capital, when the model has it.
	_capital = _chip_button("Capital")
	_capital.name = "capital"
	_capital.visible = false
	_capital.pressed.connect(func() -> void: open_overlay("parliament"))
	row.add_child(_capital)
	row.add_child(_rule())
	_status = Label.new()
	_status.theme_type_variation = "Muted"
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)
	for spec in [["Next month", 1], ["3 months", 3], ["Year", 12]]:
		var button := Button.new()
		button.text = spec[0]
		button.name = "advance_%d" % spec[1]
		button.theme_type_variation = "Primary" if spec[1] == 1 else "Quiet"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.tooltip_text = "Run the next %s" % ["month", "three months", "twelve months"][[1, 3, 12].find(spec[1])]
		var count: int = spec[1]
		button.pressed.connect(func() -> void: advance(count))
		row.add_child(button)
		_advance.append(button)
	row.add_child(_rule())
	for spec in [["Budget", "balance", "budget"], ["Parliament", "parliament", "parliament"]]:
		var button := Button.new()
		button.text = spec[0]
		button.name = "open_" + spec[2]
		button.icon = Palette.icon(spec[1])
		button.theme_type_variation = "Quiet"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var which: String = spec[2]
		button.pressed.connect(func() -> void: open_overlay(which))
		button.tooltip_text = spec[0]
		button.set_meta("words", spec[0])
		row.add_child(button)
		_wide.append(button)
	_menu = MenuButton.new()
	_menu.name = "menu"
	_menu.text = "Menu"
	_menu.flat = false
	_menu.theme_type_variation = "Quiet"
	_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_menu)
	_parliament_button = row.get_node("open_parliament")
	_bar.resized.connect(_fit_bar)
	var menu := _menu.get_popup()
	for item in [["Save", 0], ["Load", 1], ["Reload model", 2]]:
		menu.add_item(item[0], item[1])
	menu.add_separator()
	menu.add_check_item("Amounts a year", 3)
	menu.add_item("See the whole board", 4)
	var scales := PopupMenu.new()
	scales.name = "scale"
	scales.add_radio_check_item("Automatic", 100)
	for s in [100, 125, 150, 175, 200]:
		scales.add_radio_check_item("%d%%" % s, s + 1000)
	scales.id_pressed.connect(func(id: int) -> void: set_ui_scale(0.0 if id == 100 else (id - 1000) / 100.0))
	menu.add_submenu_node_item("Size of the screen", scales, 5)
	menu.add_separator()
	menu.add_item("Help", 6)
	menu.id_pressed.connect(func(id: int) -> void:
		menu_action(["save", "load", "reload", "per_year", "fit", "", "help"][id]))
	_update_menu()


## On a narrow window the Budget and Parliament buttons show only their pictograms and the
## capital stays at the centre of the board, so the bar never overflows.
func _fit_bar() -> void:
	var narrow := _bar.size.x < 1560.0
	for button in _wide:
		button.text = "" if narrow else str(button.get_meta("words"))
	_advance[1].text = "3 months" if not narrow else "+3"
	_advance[2].text = "Year" if not narrow else "+12"
	_capital.visible = not narrow and _capital_text != ""


func _rule() -> Control:
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(12, 0)
	rule.draw.connect(func() -> void:
		rule.draw_line(Vector2(6, 6), Vector2(6, rule.size.y - 6), Color(Palette.INK, 0.45), 1.0))
	return rule


func _chip_button(caption: String) -> Button:
	var button := Button.new()
	button.theme_type_variation = "Chip"
	button.size_flags_vertical = Control.SIZE_FILL
	button.custom_minimum_size = Vector2(0, BAR_HEIGHT - 14)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 7
	box.offset_right = -7
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(box)
	var label := Label.new()
	label.text = caption.to_upper()
	label.theme_type_variation = "Heading"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var value := Label.new()
	value.name = "value"
	value.add_theme_font_override("font", Palette.display(500))
	value.add_theme_font_size_override("font_size", 21)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	var change := Label.new()
	change.name = "change"
	change.add_theme_font_override("font", Palette.text(600))
	change.add_theme_font_size_override("font_size", Palette.SMALL)
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(change)
	button.set_meta("value", value)
	button.set_meta("change", change)
	button.set_meta("label", label)
	# The chip is as wide as its widest line.
	box.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.x = box.get_combined_minimum_size().x + 14.0)
	return button


func _update_menu() -> void:
	if _menu == null:
		return
	var menu := _menu.get_popup()
	var busy := game != null and game.is_busy()
	menu.set_item_disabled(menu.get_item_index(0), not started or busy or failed or lost)
	menu.set_item_disabled(menu.get_item_index(1), busy or game == null or not FileAccess.file_exists(save_path))
	menu.set_item_disabled(menu.get_item_index(2), busy or not started)
	menu.set_item_checked(menu.get_item_index(3), fmt.per_year)
	var scales: PopupMenu = menu.get_node("scale")
	for i in scales.item_count:
		var id := scales.get_item_id(i)
		scales.set_item_checked(i, (id == 100 and _scale_choice <= 0.0) or (id >= 1000 and is_equal_approx((id - 1000) / 100.0, _scale_choice)))


## The menu's actions, by name: "save", "load", "reload", "per_year", "fit", "help".
func menu_action(action: String) -> void:
	match action:
		"save":
			save_game()
		"load":
			load_game()
		"reload":
			reload_model()
		"per_year":
			show_per_year(not fmt.per_year)
		"fit":
			board.fit()
		"help":
			_show_dialog("How to play", HELP)


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
	close_popup()
	budget.build(catalogue, entries, str(play.get("government", "government")))
	politics.build(play)
	board.build(entries, play, lever_entries, _key_label)
	politics.build_groups(board)
	_build_headline()
	# Stage S7.3: the situations, as they stand now (nothing is announced for a game just
	# opened, loaded or reloaded).
	situations.clear()
	_situations_on.clear()
	for entry in catalogue.get("entries", []):
		if str(entry.get("situation", "")) != "":
			situations.append(entry)
			_situations_on[entry["name"]] = game.latest(str(entry["row"])) == true
	dilemmas = catalogue.get("dilemmas", [])
	_country.text = str(play.get("country", game.scenario_name())).to_upper()
	_parliament_button.visible = not politics.settings.is_empty()


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
	for child in _chips.get_children():
		child.queue_free()
	_chip.clear()
	for key in _headline_keys():
		var entry := _key_entry(key)
		if entry.is_empty():
			continue
		var chip := _chip_button(_key_label(key))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.name = "chip_" + key
		chip.tooltip_text = str(entry.get("doc", ""))
		var row_key: String = key
		chip.pressed.connect(func() -> void: open_indicator(str(entry["name"]), row_key, chip.get_global_rect()))
		_chips.add_child(chip)
		_chip[key] = {"button": chip, "entry": entry, "shown": null}


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


func _start_of(lever: String) -> Variant:
	var values: PackedFloat64Array = game.series(lever)
	return values[0] if not values.is_empty() else game.latest(lever)


func _refresh(stepped := false) -> void:
	var done := game.steps_done()
	_date.text = fmt.month_name(maxi(done - 1, 0)) + ("  ·  start" if done == 0 else "  ·  %d/%d" % [done, term])
	var modded := PackedStringArray()
	for mod in game.active_mods():
		modded.append(str(mod["name"]))
	_country.tooltip_text = "" if modded.is_empty() else "With " + ", ".join(modded)
	_country.text = str(play.get("country", game.scenario_name())).to_upper() + (" · WITH " + ", ".join(modded).to_upper() if not modded.is_empty() else "")
	for key in _chip:
		_show_chip(key, stepped)
	budget.refresh(func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	politics.refresh(func(name: String) -> Dictionary: return game.cells(name),
		func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row),
		game.steps_done())
	var pending: Dictionary = game.pending()
	for name in _costs.keys():
		if not pending.has(name):
			_costs.erase(name)
	var capital := _show_capital()
	_show_centre(capital)
	board.refresh(latest_value, previous_value, func(l: String) -> Variant: return game.latest(l), _start_of, pending, stepped)
	board.set_flags(_flags())
	_refresh_popup(pending, capital)
	_set_controls(not failed and not lost)


## A figure on the top bar; after a month it counts to its new value.
func _show_chip(key: String, count: bool) -> void:
	var chip: Dictionary = _chip[key]
	var entry: Dictionary = chip["entry"]
	var now: Variant = latest_value(key)
	var before: Variant = previous_value(key)
	var value: Label = chip["button"].get_meta("value")
	var change: Label = chip["button"].get_meta("change")
	var shown: Variant = chip["shown"]
	chip["shown"] = now
	if count and now != null and shown != null and typeof(now) != TYPE_BOOL and float(shown) != float(now):
		var tween: Tween = chip["button"].create_tween()
		var integer := typeof(now) == TYPE_INT
		tween.tween_method(func(k: float) -> void:
			var v: Variant = lerpf(float(shown), float(now), k)
			value.text = fmt.value(entry, int(roundf(v)) if integer else v, true, false), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		value.text = fmt.value(entry, now, true, false)
	change.text = ""
	if now != null and before != null and typeof(now) != TYPE_BOOL and float(now) != float(before):
		var d := float(now) - float(before)
		var better := _better(key)
		change.text = "▲" if d > 0.0 else "▼"
		change.add_theme_color_override("font_color", Palette.INK if better == "" else (Palette.GOOD if (d > 0.0) == (better == "high") else Palette.BAD))
		chip["button"].tooltip_text = "%s\n%s on last month" % [str(entry.get("doc", "")), fmt.change(entry, d)]


## "high" or "low" when the board says which way a row is better, "" otherwise.
func _better(key: String) -> String:
	var node: Dictionary = board.nodes.get("indicator:" + key, {})
	return str(node.get("better", ""))


## Stage S12.5: the political capital on the top bar (with what the bills waiting will
## cost); returns it, or -1 for a model without it.
func _show_capital() -> float:
	var name := str(catalogue.get("capital", ""))
	var entry: Dictionary = entries.get(name, {})
	var now: Variant = game.latest(str(entry.get("row", name))) if name != "" else null
	_capital.visible = now != null and _bar.size.x >= 1560.0
	if now == null:
		_capital_text = ""
		return -1.0
	var before: Variant = game.previous(str(entry.get("row", name)))
	var text := "Political capital %.1f" % float(now)
	if before != null and float(now) != float(before):
		text += " (%+.1f)" % (float(now) - float(before))
	var waiting := 0.0
	for cost in _costs.values():
		waiting += float(cost)
	if waiting > 0.0:
		text += " · %.1f for bills waiting" % waiting
	_capital_text = text
	var value: Label = _capital.get_meta("value")
	var change: Label = _capital.get_meta("change")
	value.text = "%.1f" % float(now)
	change.text = "%.1f waiting" % waiting if waiting > 0.0 else ""
	change.add_theme_color_override("font_color", Palette.BAD if waiting > float(now) else Palette.PENDING)
	_capital.tooltip_text = "%s\n%s" % [text, str(entry.get("doc", ""))]
	return float(now)


## The centre of the board: the government's approval (the poll rating named in
## [play.politics]; for a model without politics, the first headline figure), the months to
## the election and the political capital.
func _show_centre(capital: float) -> void:
	var settings: Dictionary = play.get("politics", {})
	var key := str(settings.get("support", ""))
	var title := "APPROVAL"
	if key == "" or _key_entry(key).is_empty():
		var keys := _headline_keys()
		key = str(keys[0]) if not keys.is_empty() else ""
		title = _key_label(key).to_upper()
	var entry := _key_entry(key)
	var centre := {"title": title, "figure": fmt.value(entry, latest_value(key), true, false) if not entry.is_empty() else "–"}
	var now: Variant = latest_value(key)
	var before: Variant = previous_value(key)
	if now != null and before != null and typeof(now) != TYPE_BOOL and float(now) != float(before):
		var d := float(now) - float(before)
		centre["change"] = ("▲ " if d > 0.0 else "▼ ") + fmt.change(entry, d)
		centre["change_colour"] = Palette.GOOD if d > 0.0 else Palette.BAD
	var months: Variant = game.latest(str(settings.get("months_to_election", "")))
	if months != null:
		centre["election"] = "Election in %d months" % int(months) if int(months) > 0 else "Election this month"
	if capital >= 0.0:
		var waiting := 0.0
		for cost in _costs.values():
			waiting += float(cost)
		centre["capital"] = "Capital %.1f%s" % [capital, (" · %.1f waiting" % waiting) if waiting > 0.0 else ""]
		centre["capital_colour"] = Palette.BAD if waiting > capital else (Palette.PENDING if waiting > 0.0 else Palette.INK)
	board.centre = centre


func _set_controls(enabled: bool) -> void:
	var busy := game != null and game.is_busy()
	# Stage S9.1: no month runs while a dilemma waits for an answer.
	var waiting := not unanswered_dilemmas().is_empty()
	for button in _advance:
		button.disabled = not enabled or busy or waiting
		button.tooltip_text = "Answer the question put to you first" if waiting else button.tooltip_text
	_status.text = "working…" if busy else ""
	_update_menu()


# ---------------------------------------------------------------------------- popups

## Opens the popup of a board node: "policy:<key>", "indicator:<row>", "group:<key>",
## "flag:<key>" or "centre" (Parliament).
func open_node(key: String, from := Rect2()) -> void:
	if not board.nodes.has(key):
		return
	var node: Dictionary = board.nodes[key]
	var origin := _node_rect(key) if from == Rect2() else from
	match str(node["kind"]):
		"centre":
			open_overlay("parliament")
			return
		"flag":
			if str(node.get("tone", "")) == "ask":
				ask_dilemma()
			elif str(node.get("name", "")) != "":
				open_indicator(str(node["name"]), str(node.get("row", "")), origin)
			return
	board.select(key)
	popup.open(func() -> Control: return _node_content(key), origin)
	_after_open()


## Opens the popup of any catalogue entry: a board indicator's if it is on the board, or
## the same kind of popup for one off it (a budget line, a top-bar figure, a cause followed).
func open_indicator(name: String, row_key := "", origin := Rect2()) -> void:
	var entry: Dictionary = entries.get(name, {})
	if entry.is_empty():
		return
	if row_key == "":
		row_key = str(entry.get("row", ""))
	if board.nodes.has("indicator:" + row_key):
		if origin == Rect2():
			origin = _node_rect("indicator:" + row_key)
		board.select("indicator:" + row_key)
		popup.open(func() -> Control: return _node_content("indicator:" + row_key), origin)
	else:
		if origin == Rect2():
			origin = Rect2(get_viewport_rect().size / 2.0, Vector2.ONE)
		popup.open(func() -> Control: return _entry_content(name, row_key), origin)
	_after_open()


func _after_open() -> void:
	_update_input()
	_refresh_popup(game.pending(), _show_capital())
	_request_forecast()


func _node_rect(key: String) -> Rect2:
	var node: Dictionary = board.nodes.get(key, {})
	if node.is_empty():
		return Rect2(get_viewport_rect().size / 2.0, Vector2.ONE)
	var p: Vector2 = board.to_screen(node["pos"]) + board.position
	var r: float = node["r"] * board.zoom
	return Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)


func _node_content(key: String) -> Control:
	var node: Dictionary = board.nodes[key]
	if node["kind"] == "policy":
		var card := LeverPanel.new()
		card.fmt = fmt
		card.name = "policy_card"
		card.wide = get_viewport_rect().size.x >= LeverPanel.WIDE_FROM
		var lever_entries := []
		for lever in node["levers"]:
			lever_entries.append(entries[lever])
		card.build(node, lever_entries, bool(catalogue.get("legislature", false)), _start_of)
		card.lever_changed.connect(_lever_typed)
		card.lever_cancelled.connect(func(name: String) -> void:
			game.cancel_lever(name)
			_refresh())
		card.follow.connect(func(name: String) -> void: _follow(name))
		return card
	if node["kind"] == "group":
		return _group_content(key)
	return _entry_content(str(node["name"]), str(node["row"]), key)


func _entry_content(name: String, row_key: String, key := "") -> Control:
	var entry: Dictionary = entries.get(name, {})
	var node: Dictionary = board.nodes.get(key, {})
	var card := IndicatorCard.new()
	card.fmt = fmt
	card.name = "indicator_card"
	var label := _key_label(row_key) if row_key != "" and not _key_entry(row_key).is_empty() else str(entry.get("label", name))
	var compare := []
	for k in board.keys_of("indicator"):
		var other: Dictionary = board.nodes[k]
		var o: Dictionary = entries.get(other["name"], {})
		if other["row"] != row_key and [o.get("shown_unit", ""), fmt.is_money(o), fmt.is_rate(o)] == [entry.get("shown_unit", ""), fmt.is_money(entry), fmt.is_rate(entry)]:
			compare.append([other["row"], other["label"]])
	var movers := []
	var found: Array = board.movers(key) if key != "" else board.movers_for(row_key, name)
	for m in found:
		movers.append([m[0], board.nodes[m[0]]["label"], m[1], m[2]])
	var icon: Texture2D = node.get("icon", Palette.icon("indicator"))
	card.build(name, row_key, entry, label, str(node.get("area", "")), icon, entries, play, _breakdowns_of(name), compare, movers)
	card.follow.connect(func(target: String) -> void: _follow(target))
	card.trace.trail = PackedStringArray([name])
	card.trace.show_waiting(name)
	if str(entry.get("kind", "")) in ["var", "flow", "state", "account"]:
		game.request_explanation(name)
	return card


## The breakdowns shown in an entry's popup: those whose national line it is
## (`breakdown_totals`), or, for `breakdown_all`, every other.
func _breakdowns_of(name: String) -> Array:
	var out := []
	var totals: Dictionary = play.get("breakdown_totals", {}) if play.get("breakdown_totals", {}) is Dictionary else {}
	for b in play.get("breakdowns", []):
		var total := str(totals.get(str(b), ""))
		if total == name or (total == "" and str(play.get("breakdown_all", "")) == name):
			out.append(str(b))
	return out


## Stage S13.4: an interest group's popup, and a request for eight of its households.
func _group_content(key: String) -> Control:
	var node: Dictionary = board.nodes[key]
	var card := GroupCard.new()
	card.fmt = fmt
	card.name = "group_card"
	card.wide = get_viewport_rect().size.x >= LeverPanel.WIDE_FROM
	card.index = _group_index(node)
	var movers := []
	for m in board.movers(key):
		movers.append([m[0], board.nodes[m[0]]["label"], m[1], m[2]])
	card.build(node, entries.get(node["name"], {}), _group_drivers(), movers)
	card.follow.connect(func(target: String) -> void: _follow(target))
	card.household_opened.connect(func(record: Dictionary) -> void:
		popup.push(func() -> Control: return _household_content(record)))
	var house: Dictionary = play.get("web", {}).get("household", {})
	var flag := str(node.get("households", ""))
	if flag != "" and not house.is_empty() and game.has_method("request_records"):
		var columns := PackedStringArray([flag])
		for field in ["support", "net_income", "change", "adults", "children", "region", "type"]:
			if str(house.get(field, "")) != "":
				columns.append(str(house[field]).get_slice(":", 0))
		for spec in house.get("account", []):
			columns.append(str(spec).trim_prefix("-"))
		game.call("request_records", str(house.get("entity", "household")), flag, 8, columns, key)
	return card


## The group's place in its dimension: the member whose share of the electorate is the
## group's own (the [play.web] row), so no member names are needed.
func _group_index(node: Dictionary) -> int:
	var share: Variant = game.latest(str(node.get("share", "")))
	var cells: Dictionary = game.cells(str(play.get("web", {}).get("group_share", "group_share")))
	var values: PackedFloat64Array = cells.get("values", PackedFloat64Array())
	var best := -1
	for i in values.size():
		if share != null and (best < 0 or absf(values[i] - float(share)) < absf(values[best] - float(share))):
			best = i
	return best


## The drivers of a group's vote: [[plain name, value name]], from [play.web].
func _group_drivers() -> Array:
	var web: Dictionary = play.get("web", {})
	var drivers: Dictionary = web.get("group_drivers", {})
	var labels: Dictionary = web.get("group_driver_labels", {})
	var out := []
	for k in drivers:
		out.append([str(labels.get(k, entries.get(str(drivers[k]), {}).get("label", k))), str(drivers[k])])
	return out


## The words for a household's data columns: column -> the labels of its dimension.
func _household_words() -> Dictionary:
	var house: Dictionary = play.get("web", {}).get("household", {})
	var words := {}
	for field in ["region", "type"]:
		var spec := str(house.get(field, ""))
		for d in catalogue.get("dims", []):
			if str(d["name"]) == spec.get_slice(":", 1):
				words[spec.get_slice(":", 0)] = d["labels"]
	return words


func _household_content(record: Dictionary) -> Control:
	var account := GroupCard.HouseholdAccount.new()
	account.name = "household_card"
	account.build(record, play.get("web", {}).get("household", {}), entries, fmt, _household_words())
	return account


## Following a cause inside the popup: an entry's name or a board key.
func _follow(target: String) -> void:
	if target.begins_with("policy:") or target.begins_with("indicator:") or target.begins_with("group:"):
		if board.nodes.has(target):
			board.select(target)
			popup.push(func() -> Control: return _node_content(target))
			_refresh_popup(game.pending(), _show_capital())
			_request_forecast()
			return
	else:
		var entry: Dictionary = entries.get(target, {})
		if entry.is_empty():
			return
		var row_key := str(entry.get("row", ""))
		if board.nodes.has("indicator:" + row_key):
			popup.push(func() -> Control: return _node_content("indicator:" + row_key))
		elif str(entry.get("kind", "")) == "lever" and board.policy_of(target) != "":
			var key := board.policy_of(target)
			popup.push(func() -> Control: return _node_content(key))
		else:
			popup.push(func() -> Control: return _entry_content(target, row_key))
	_refresh_popup(game.pending(), _show_capital())
	_request_forecast()


func _refresh_popup(pending: Dictionary, capital: float) -> void:
	if popup == null or not popup.is_open():
		return
	var card := policy_card()
	if card != null:
		card.refresh(func(name: String) -> Variant: return game.latest(name), pending, _costs, capital)
		var markers := []
		for c in game.changes():
			if c.get("passed", true) and card.levers.has(str(c["lever"])):
				var entry: Dictionary = entries.get(c["lever"], {})
				markers.append({"step": c["step"], "text": "%s → %s" % [entry.get("label", c["lever"]), fmt.value(entry, c["value"], false, false)]})
		card.show_history(game.history_steps(), game.series(card.chart_lever()), markers)
		if game.has_method("vote_preview"):
			for lever in card.levers:
				if pending.has(lever):
					var typed: Variant = float(pending[lever]) / fmt.minor if entries.get(lever, {}).get("money", false) else pending[lever]
					card.show_vote(lever, game.call("vote_preview", lever, typed), capital - _waiting_except(lever))
	var group := group_card()
	if group != null:
		group.refresh(func(r: String) -> Variant: return game.latest(r), func(r: String) -> Variant: return game.previous(r),
			func(name: String) -> Dictionary: return game.cells(name), _group_drivers())
		var support := str(play.get("politics", {}).get("support", ""))
		group.show_history(game.history_steps(), func(r: String) -> PackedFloat64Array: return game.series(r),
			[support, "The country"] if support != "" else [])
	var ind := indicator_card()
	if ind != null:
		var node: Dictionary = board.nodes.get("indicator:" + ind.row, {})
		ind.refresh(latest_value, previous_value, str(node.get("better", "")))
		var markers := []
		for c in game.changes():
			if c.get("passed", true):
				var entry: Dictionary = entries.get(c["lever"], {})
				markers.append({"step": c["step"], "text": "%s → %s" % [entry.get("label", c["lever"]), fmt.value(entry, c["value"], false, false)]})
		ind.show_history(game.history_steps(), markers, func(r: String) -> PackedFloat64Array: return game.series(r))
		if ind.breakdown != null:
			ind.breakdown.refresh(func(name: String) -> Dictionary: return game.cells(name),
				func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	popup.relayout()


## The political capital the bills waiting would spend, leaving out one lever's.
func _waiting_except(lever: String) -> float:
	var total := 0.0
	for name in _costs:
		if name != lever:
			total += maxf(float(_costs[name]), 0.0)
	return total


func close_popup() -> void:
	if popup != null:
		popup.close()


## "policy", "indicator", "group", "household" or "" for the popup open now.
func popup_kind() -> String:
	if popup == null or not popup.is_open():
		return ""
	if popup.content is LeverPanel:
		return "policy"
	if popup.content is GroupCard:
		return "group"
	if popup.content is GroupCard.HouseholdAccount:
		return "household"
	return "indicator"


func group_card() -> GroupCard:
	return popup.content as GroupCard if popup != null and popup.is_open() else null


func policy_card() -> LeverPanel:
	return popup.content as LeverPanel if popup != null and popup.is_open() else null


func indicator_card() -> IndicatorCard:
	return popup.content as IndicatorCard if popup != null and popup.is_open() else null


## The "why it moved" panel of the popup open now, or null.
func current_trace() -> Control:
	var card := indicator_card()
	return card.trace if card != null else null


## Types a value into a lever's control, in the policy's popup (opened if need be), as a
## player would: money in major units a step, rates in percent.
func type_lever(lever: String, value: float) -> void:
	var key := board.policy_of(lever)
	if key == "":
		push_error("no policy on the board holds %s" % lever)
		return
	var card := policy_card()
	if card == null or card.key != key:
		open_node(key)
		card = policy_card()
	card.type_value(lever, value)


## Points at a board node, as the pointer does.
func hover(key: String) -> void:
	board.set_hover(key)


## Every lever on the board (the player's policies).
func board_levers() -> PackedStringArray:
	var out := PackedStringArray()
	for key in board.keys_of("policy"):
		out.append_array(board.nodes[key]["levers"])
	return out


# ---------------------------------------------------------------------------- sheets

## Opens a sheet over the board: "budget" or "parliament".
func open_overlay(which: String) -> void:
	close_popup()
	var sheet: Sheet = _budget_sheet if which == "budget" else _parliament_sheet
	if which == "parliament" and politics.settings.is_empty():
		return
	for other in [_budget_sheet, _parliament_sheet]:
		if other != sheet:
			other.close()
	sheet.open()
	_refresh()
	_update_input()


func close_overlay() -> void:
	for sheet in [_budget_sheet, _parliament_sheet]:
		sheet.close()
	_update_input()


## Which sheet is open: "budget", "parliament" or "".
func overlay_open() -> String:
	if _budget_sheet.visible:
		return "budget"
	if _parliament_sheet.visible:
		return "parliament"
	return ""


func _update_input() -> void:
	var covered: bool = popup.is_open()
	for sheet in _sheets.get_children():
		covered = covered or (sheet as Control).visible
	board.input_enabled = not covered
	if covered:
		board.set_hover("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if popup.is_open():
			close_popup()
		else:
			for i in range(_sheets.get_child_count() - 1, -1, -1):
				var sheet: Sheet = _sheets.get_child(i)
				if sheet.visible and sheet.closable:
					sheet.close()
					break
		get_viewport().set_input_as_handled()


func _show_dialog(title: String, bbcode: String) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = _new_sheet(title, 720.0)
	_dialog.add_text(bbcode)
	_dialog.closed.connect(func() -> void: _dialog.queue_free.call_deferred())
	_dialog.open()
	_update_input()


# ---------------------------------------------------------------------------- actions

## Shows flows at an annual rate, or per step.
func show_per_year(on: bool) -> void:
	fmt.per_year = on
	if game != null and catalogue.size() > 0:
		_model_changed()
		_refresh()


func advance(months: int) -> void:
	if failed or lost or game.is_busy():
		return
	if not unanswered_dilemmas().is_empty():
		ask_dilemma()
		return
	close_popup()
	game.advance(months)
	_set_controls(true)


## True when the month buttons can be pressed.
func can_advance() -> bool:
	return not _advance[0].disabled


func _lever_typed(name: String, raw: String) -> void:
	var cost: float = game.bill_cost(name, raw)
	var refused := game.set_lever(name, raw)
	if refused == "" and cost >= 0.0:
		_costs[name] = cost
	else:
		_costs.erase(name)
	if refused != "":
		_show_message("[b]%s was not changed[/b]: %s" % [entries.get(name, {}).get("label", name), refused], true)
	_refresh()
	_forecast_timer.start()


## Stage S13.3 contract: what the changes waiting in the open policy would do in a year,
## against the same year without them. Quiet until the bridge has request_forecast.
func _request_forecast() -> void:
	var card := policy_card()
	if card == null:
		return
	if not game.has_method("request_forecast"):
		card.hide_year()
		return
	var pending: Dictionary = game.pending()
	var changes := {}
	for lever in card.levers:
		if pending.has(lever):
			# Without this policy's waiting change: its setting now, as a person types it.
			var now: Variant = game.latest(lever)
			changes[lever] = float(now) / fmt.minor if entries.get(lever, {}).get("money", false) else now
	if changes.is_empty():
		card.hide_year()
		return
	if game.call("request_forecast", changes, 12, card.key):
		card.show_year({}, [], true)


## The rows the year-ahead table may list: the budget balance first, then every indicator
## and group on the board and every line of the budget.
func _year_rows() -> Array:
	var out := []
	var seen := {}
	var balance := "indicator:budget_balance"
	var keys := ([balance] if board.nodes.has(balance) else []) + Array(board.keys_of("indicator")) + Array(board.keys_of("group"))
	for key in keys:
		var node: Dictionary = board.nodes[key]
		if not seen.has(node["row"]):
			seen[node["row"]] = true
			out.append([node["row"], node["label"], entries.get(node["name"], {}), node["kind"], node["tier"], node["better"], key])
	for line in budget._lines:
		if not seen.has(line["row"]):
			seen[line["row"]] = true
			out.append([line["row"], str(line["entry"].get("label", line["name"])), line["entry"], "budget", 2])
	return out

## Stage S13.3 contract: the effects table (each lever nudged a step, a year on), asked
## for after a game opens and after each month, once the screen is idle.
func _want_effects() -> void:
	if not game.has_method("request_effects"):
		return
	_effects_timer.start()


## True from asking for the effects table until its last lever is in (or it went stale).
var effects_running := false


func _request_effects() -> void:
	if not started or game.is_busy() or failed:
		_effects_timer.start()
		return
	effects_running = game.call("request_effects", board_levers(), 12)

## An effects event: each row's change, as a share of where it would be otherwise (for a
## rate, ten times the change in points), signed.
func _take_effects(event: Dictionary) -> void:
	var lever := str(event.get("lever", ""))
	if str(event.get("error", "")) != "" or lever == "":
		return
	# The table nudges a lever down when up would pass its top: signs are put as for a rise.
	var up := -1.0 if float(event.get("step", 1.0)) < 0.0 else 1.0
	var strengths := {}
	var table: Dictionary = event.get("rows", {})
	for row in table:
		var pair: Variant = table[row]
		var d := 0.0
		var base := 1.0
		if pair is Array and pair.size() == 2:
			d = float(pair[1]) - float(pair[0])
			base = maxf(absf(float(pair[0])), 1e-9)
		else:
			d = float(pair)
		var entry: Dictionary = rows.get(row, {})
		strengths[row] = up * (d * 10.0 if fmt.is_rate(entry) else d / base)
	board.effects[lever] = strengths
	board.effects_changed()


func save_game() -> void:
	game.save_game(save_path)
	_set_controls(true)


func load_game() -> void:
	game.load_game(save_path)
	_set_controls(true)


func reload_model() -> void:
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
	_message.add_theme_stylebox_override("panel", _notice_style(Palette.BAD if problem else Palette.OCHRE))
	_message.visible = true


## A notice: card stock edged in the notice's colour, with a thick band down the left.
static func _notice_style(colour: Color) -> StyleBoxFlat:
	var box := Palette.card(16, 6, 2)
	box.border_color = colour.darkened(0.1)
	box.border_width_left = 10
	box.content_margin_left = 24
	return box


func notice_visible() -> bool:
	return _message.visible


func notice_text() -> String:
	return _message_text.get_parsed_text() if _message.visible else ""


func capital_text() -> String:
	return _capital_text


func title_text() -> String:
	return _country.text + " · " + _date.text


func flag_text(key: String) -> String:
	return board.flag_text(key)


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


## Stage S7.3 and S9.1: the flags under the centre: each situation in force with the month
## it began, each question waiting (press to answer), each answer given and in force.
func _flags() -> Array:
	var out := []
	for entry in situations:
		var row := str(entry["row"])
		if game.latest(row) != true:
			continue
		var text := str(entry.get("label", entry["name"]))
		var since := situation_onset(row)
		out.append({"key": "situation_" + str(entry["name"]), "text": text, "since": (" · since " + fmt.month_name(since)) if since >= 0 else "", "tone": "good" if str(entry["situation"]) == "good" else "bad",
			"doc": str(entry.get("doc", "")), "name": str(entry["name"]), "row": row})
	var pending: Dictionary = game.pending()
	var waiting := unanswered_dilemmas()
	for d in dilemmas:
		var name := str(d["name"])
		var label := str(d.get("label", name))
		var options: Array = d.get("options", [])
		if waiting.has(d):
			out.append({"key": "dilemma_" + name, "text": "Decide: " + label, "tone": "ask", "doc": str(d.get("doc", ""))})
			continue
		var text := ""
		if pending.has(name):
			var k := int(pending[name])
			if k >= 1 and k <= options.size():
				text = "%s: %s · from next month" % [label, str(options[k - 1].get("label", ""))]
		else:
			var choice: Variant = game.latest(name + "_choice")
			var age: Variant = game.latest(name + "_age")
			if choice != null and int(choice) >= 1 and int(choice) <= options.size() and age != null:
				var option: Dictionary = options[int(choice) - 1]
				var months := int(option.get("months", 0))
				# The answer's month is the step `age` months before the last one run.
				var last := game.steps_done() - 1 - int(age) + months - 1
				if months == 0:
					text = "%s: %s" % [label, str(option.get("label", ""))]
				elif last >= game.steps_done():
					text = "%s: %s · until %s" % [label, str(option.get("label", "")), fmt.month_name(last)]
		if text != "":
			out.append({"key": "dilemma_" + name, "text": text, "tone": "plain", "doc": str(d.get("doc", ""))})
	return out


## Stage S9.1: the dilemmas open now with no answer given for next month, in model order.
func unanswered_dilemmas() -> Array:
	var out := []
	if game == null or not started:
		return out
	var pending: Dictionary = game.pending()
	for d in dilemmas:
		var name := str(d["name"])
		if game.latest(name + "_open") == true and not pending.has(name):
			out.append(d)
	return out


## Stage S9.1: puts the first dilemma waiting for an answer to the player, on a sheet with
## a button for each answer. Closing it leaves the question flagged on the board.
func ask_dilemma() -> void:
	var waiting := unanswered_dilemmas()
	if waiting.is_empty():
		return
	var d: Dictionary = waiting[0]
	var name := str(d["name"])
	if dilemma_dialog != null and is_instance_valid(dilemma_dialog):
		if dilemma_dialog.visible and _dilemma_asked == name:
			return
		dilemma_dialog.queue_free()
	close_popup()
	_dilemma_asked = name
	var sheet := _new_sheet(str(d.get("label", name)), 720.0)
	sheet.name = "dilemma_dialog"
	dilemma_dialog = sheet
	sheet.body.add_child(Palette.caps("A question for the government"))
	var lines := PackedStringArray()
	if str(d.get("doc", "")) != "":
		lines.append(str(d["doc"]) + ".\n")
	for option in d.get("options", []):
		var line := "[b]%s[/b]" % str(option.get("label", option["name"]))
		if str(option.get("doc", "")) != "":
			line += ": " + str(option["doc"])
		lines.append(line + ".\n")
	lines.append("[color=#55606c]Your answer takes effect next month; no month runs until you give one.[/color]")
	sheet.add_text("\n".join(lines))
	var options: Array = d.get("options", [])
	for i in options.size():
		var answer := i + 1
		sheet.add_action(str(options[i].get("label", options[i]["name"])), func() -> void: answer_dilemma(name, answer), i == 0)
	sheet.open()
	_update_input()


## The title of the question on screen, or "" when none is.
func dilemma_title() -> String:
	if dilemma_dialog != null and is_instance_valid(dilemma_dialog) and dilemma_dialog.visible:
		return str(dilemma_dialog.title)
	return ""


## Stage S9.1: answers dilemma `name` with its answer number `answer` (from 1), for next
## month, then asks the next dilemma waiting, if any.
func answer_dilemma(name: String, answer: int) -> void:
	var refused := game.set_lever(name, answer)
	if refused != "":
		_show_message("[b]The answer was not taken[/b]: " + refused, true)
	if dilemma_dialog != null and is_instance_valid(dilemma_dialog):
		dilemma_dialog.close()
	_refresh()
	ask_dilemma()


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
	var short := PackedStringArray()  # stage S12.5: refused for want of political capital
	for i in range(_changes_seen, changes.size()):
		var c: Dictionary = changes[i]
		if c.get("passed", true):
			continue
		var entry: Dictionary = entries.get(c["lever"], {})
		var what := "%s to %s, in %s" % [entry.get("label", c["lever"]), fmt.value(entry, c["value"], false, true),
			fmt.month_name(int(c["step"]))]
		if c.get("refused", false):
			short.append("%s: it needed %.1f political capital" % [what, float(c["cost"])])
		else:
			lines.append("%s: %d for, %d against" % [what, int(c["votes_for"]), int(c["seats"]) - int(c["votes_for"])])
	_changes_seen = changes.size()
	var notes := PackedStringArray()
	if not lines.is_empty():
		notes.append("[b]The House of Commons voted down %s[/b]\n%s\nYour government lacks a majority of its own; its partners and the opposition vote by their side of politics." % [
			"a bill" if lines.size() == 1 else "%d bills" % lines.size(), "\n".join(lines)])
	if not short.is_empty():
		notes.append("[b]Not enough political capital: %s not put to the Commons[/b]\n%s\nCapital comes back each month, faster while the government is popular." % [
			"a bill was" if short.size() == 1 else "%d bills were" % short.size(), "\n".join(short)])
	if not notes.is_empty():
		_show_message("\n\n".join(notes))


func _process(_delta: float) -> void:
	if game == null or not started:
		return
	var events := game.poll()
	var stepped := false
	for event in events:
		match str(event.get("kind", event.get("type", ""))):
			"stepped":
				stepped = true
				effects_running = false
				_announce_votes()
				_announce_situations()
				_announce_election()
				ask_dilemma.call_deferred()
				if game.steps_done() >= term and not term_announced:
					_announce_term.call_deferred()
			"failed":
				failed = true
				_show_message("[b]The simulation stopped[/b]\n%s\n\nLoad your save, or reload a corrected model." % event["error"], true)
			"explained":
				var trace := current_trace()
				var card := indicator_card()
				if trace != null and card.name_shown == str(event.get("name", event.get("explanation", {}).get("name", ""))):
					if event.has("explanation"):
						trace.show_explanation(event["explanation"])
					else:
						trace.show_error(event["name"], event["error"])
					popup.relayout()
			"forecast":
				var card := policy_card()
				if card != null and str(event.get("tag", "")) == card.key:
					if str(event.get("error", "")) != "":
						card.hide_year()
					else:
						card.show_year(event.get("rows", {}), _year_rows())
					popup.relayout()
			"effects":
				_take_effects(event)
			"records":
				var group := group_card()
				if group != null and str(event.get("tag", "")) == group.key:
					group.show_households(event.get("records", []), play.get("web", {}).get("household", {}), _household_words())
					popup.relayout()
			"effects_done":
				effects_running = false
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
					_model_changed()
					ask_dilemma.call_deferred()
					var note := ""
					var missing: PackedStringArray = event.get("missing_mods", PackedStringArray())
					if not missing.is_empty():
						note = "[b]Mods this game was played with are missing[/b] and were left out: %s.\n" % ", ".join(missing)
					if event.get("migrated", false):
						note += _migration_note(event)
					if note != "":
						_show_message(note)
					stepped = true
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
					stepped = true
	if not events.is_empty():
		_refresh(stepped)
		if stepped:
			_want_effects()
	elif _status.text == "working…" and not game.is_busy():
		_set_controls(not failed and not lost)
