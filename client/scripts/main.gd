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
## flag_text(key), dilemma_title(), can_advance(), board_levers(). Stage S13.5: a growing
## board: available_policies(area), open_introduce(area), introduce_policy(key, value),
## repeal_policy(key). Stage S15.1: open_add_policy(key), add_sheet(), search_for(words),
## open_situation(name), situation_node(name).

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
const MonthReport := preload("res://scripts/month_report.gd")
const Guide := preload("res://scripts/guide.gd")
const Sound := preload("res://scripts/sound.gd")
const AddPolicy := preload("res://scripts/add_policy.gd")
const Search := preload("res://scripts/search.gd")
const Strip := preload("res://scripts/strip.gd")
const KeyPage := preload("res://scripts/key_page.gd")
const Plate := preload("res://scripts/plate.gd")

const SETTINGS := "user://settings.cfg"
const BAR_HEIGHT := 64.0
## Stage S14.1: the strip under the top bar (situations, the one-line notices).
const STRIP_HEIGHT := Strip.HEIGHT
## Stage S19: the keys, and the credits the open material asks for. (It was nine paragraphs
## on how to play: the board is to be understood by using it, and "?" is its key.)
const HELP := """[table=2][cell][b]Space, Enter[/b]      [/cell][cell]Next month[/cell]
[cell][b]A[/b][/cell][cell]Add policy[/cell]
[cell][b]/, Ctrl+F[/b][/cell][cell]Search[/cell]
[cell][b]B[/b][/cell][cell]The Budget[/cell]
[cell][b]P[/b][/cell][cell]Parliament[/cell]
[cell][b]K[/b][/cell][cell]The key[/cell]
[cell][b]Tab, Shift+Tab[/b][/cell][cell]The next control, the one before[/cell]
[cell][b]Esc[/b][/cell][cell]Close what is on top[/cell]
[cell][b]F11[/b][/cell][cell]The whole screen, or a window[/cell][/table]

[color=#505a66]Pictograms from game-icons.net by Lorc, Delapouite and others, CC BY 3.0. Type: Jost and IBM Plex Sans, SIL Open Font License. Sounds: Kenney's Interface Sounds, CC0.[/color]"""

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
## Stage S16.1: true while the bills waiting cost more political capital than there is.
var _capital_short := false
## Stage S7.1: shown until a game starts, when the client starts without `--scenario`.
var start_screen: StartScreen
## True once a game has started.
var started := false
## Stage S13.6: true while a new game's opening month runs.
var _opening := false
## Stage S13.6: the month's report, what the screen stood at before the months it covers,
## and the first-minutes guide.
var report: MonthReport
var _report_from := {}
var guide: Guide

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
var _vital: HBoxContainer  # stage S16.1: approval and capital, kept on the bar always
var _advance: Array[Button] = []
var _menu: MenuButton
var _parliament_button: Button
## Top-bar buttons that drop their words on a narrow window, keeping their pictograms.
var _wide: Array[Button] = []
var _status: Label
var strip: Strip
var _key_sheet: Sheet
## Stage S15.1: the Add policy sheet (built each time it opens) and its content; search.
var _add_sheet: Sheet
var add_list: AddPolicy
var search: Search
## Stage S15.1: each situation's node on the board: situation name -> board key.
var _situation_nodes := {}
var _forecast_timer: Timer
var _hover_timer: Timer
var _effects_timer: Timer
var _scale_choice := 0.0  # 0 for automatic
## Stage S14.1: a month's events arrived and the screen is not yet refreshed for them (while
## a run of months goes on only the date follows them).
var _stepped_waiting := false
var _queued := 0  # months asked for while the engine was busy


## True while months asked for wait for the engine.
func advance_queued() -> bool:
	return _queued > 0


func _ready() -> void:
	theme = Palette.make_theme()
	Sound.load_settings()
	_apply_scale(_saved_scale())
	var kept := ConfigFile.new()
	if kept.load(SETTINGS) == OK and bool(kept.get_value("ui", "fullscreen", false)) and DisplayServer.get_name() != "headless":
		fullscreen = true
		get_window().mode = Window.MODE_FULLSCREEN
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
		start_from_screen(path, mods, resume, language))
	_set_controls(false)


## Opens a scenario with the mods chosen beyond its own, in a language from the model's
## text ("" for its own words), and shows its board.
func start(path: String, mods := PackedStringArray(), language := "") -> void:
	scenario_path = path
	close_popup()
	_report_from = {}
	report.title = ""
	report.visible = false
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


## The start screen's choice: a saved game continued, or a new game with its opening month.
func start_from_screen(path: String, mods: PackedStringArray, resume: bool, language := "") -> void:
	start(path, mods, language)
	if resume and started:
		load_game()
	elif started:
		open_first_month()


## Stage S13.6: a new game from the start screen opens with the scenario's base month
## played (the player takes office with January's figures in; their first changes take
## effect the month after), so no figure on the board is ever blank. A game started with
## --scenario stays at step 0, where the scripted checks count from, and shows the awaiting
## state instead. The first-minutes guide follows the opening month.
func open_first_month() -> void:
	_opening = true
	game.advance(1)
	_set_controls(true)


## True while a game has run no month yet: its figures are awaited.
func awaiting() -> bool:
	return started and game.steps_done() == 0


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
	board.offset_top = BAR_HEIGHT + STRIP_HEIGHT
	board.node_pressed.connect(func(key: String) -> void: open_node(key))
	add_child(board)
	# Stage S14.1: the strip under the top bar: the situations and the one-line notices.
	strip = Strip.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = BAR_HEIGHT
	strip.offset_bottom = BAR_HEIGHT + STRIP_HEIGHT
	strip.flag_pressed.connect(_open_flag)
	strip.line_pressed.connect(func(full: String) -> void: _show_dialog("Notice", full))
	add_child(strip)
	_build_bar()
	add_child(search.results)
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
	_parliament_sheet = _new_sheet("Parliament", 1000.0)
	_parliament_sheet.body.add_child(politics)
	popup = PopupCard.new()
	popup.name = "popup"
	popup.top_margin = BAR_HEIGHT
	add_child(popup)
	popup.closed.connect(func() -> void:
		if search.text.strip_edges() == "":
			board.light("")
		board.select("")
		_update_input())
	_forecast_timer = Timer.new()
	_forecast_timer.one_shot = true
	# Stage S14.4: a newer forecast cancels an older one in the bridge, so a short pause will do.
	_forecast_timer.wait_time = 0.05
	_forecast_timer.timeout.connect(_request_forecast)
	add_child(_forecast_timer)
	# Stage S14.1: the effects table is asked for a moment after a month is shown (was 1.5 s).
	_effects_timer = Timer.new()
	_effects_timer.one_shot = true
	_effects_timer.wait_time = 0.3
	_effects_timer.timeout.connect(_request_effects)
	add_child(_effects_timer)
	# Stage S13.6: the month's report, the first-minutes guide, sounds.
	report = MonthReport.new()
	report.top_margin = BAR_HEIGHT + STRIP_HEIGHT
	report.line_pressed.connect(func(key: String) -> void:
		if key.begins_with("entry:"):
			open_indicator(key.trim_prefix("entry:"))
		elif key.begins_with("situation:"):
			open_situation(key.trim_prefix("situation:"))
		elif key.begins_with("add:"):
			open_add_policy(key.trim_prefix("add:"))
		elif key == "election":
			open_overlay("parliament")
		else:
			open_node(key))
	add_child(report)
	# Under the popups and the sheets. Stage S18: it stood above the sheets (they are added
	# before the popup), so the report of a month with an election or a question lay over the
	# left of election night's sheet or the question's (tests/plates_check.gd).
	move_child(report, _sheets.get_index())
	_date.mouse_filter = Control.MOUSE_FILTER_STOP
	_date.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_date.tooltip_text = "The month's report"
	_date.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if report.visible:
				report.dismiss()
			else:
				close_popup()
				report.reopen())
	_date.mouse_entered.connect(func() -> void: _date.add_theme_color_override("font_color", Palette.BLUE))
	_date.mouse_exited.connect(func() -> void: _date.remove_theme_color_override("font_color"))
	guide = Guide.new()
	guide.finished.connect(func() -> void:
		if guide.remember:
			_save_setting("guide", "seen", true))
	add_child(guide)
	# Stage S16.1: the top bar over popups and sheets (their veils start under it), so the
	# capital and approval on it stay readable whatever is open; the guide stays over all.
	move_child(_bar, guide.get_index())
	move_child(search.results, guide.get_index())
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = 0.25
	_hover_timer.timeout.connect(_hover_first)
	add_child(_hover_timer)
	board.hover_changed.connect(func(key: String) -> void:
		if key.begins_with("policy:"):
			_hover_timer.start()
		if key != "":
			Sound.play("tick"))
	# Every button and slider shows the pointing hand, wherever it is made.
	get_tree().node_added.connect(func(node: Node) -> void:
		if (node is BaseButton and not (node as BaseButton).disabled) or node is Slider:
			(node as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND)


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
	band.content_margin_left = 16
	band.content_margin_right = 8
	band.content_margin_top = 4
	band.content_margin_bottom = 8
	_bar.add_theme_stylebox_override("panel", band)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_bar.add_child(row)
	var where := VBoxContainer.new()
	where.add_theme_constant_override("separation", -4)  # off the scale: closes up the leading between the country and the date
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(where)
	_country = Label.new()
	_country.theme_type_variation = "Heading"
	_country.add_theme_color_override("font_color", Palette.INK)
	_country.mouse_filter = Control.MOUSE_FILTER_PASS
	# Stage S17.1: no wider than the month under it: a long name (a country with its mods) is
	# cut short with an ellipsis, and whole in its tooltip.
	_country.clip_text = true
	_country.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.add_child(_country)
	_date = Label.new()
	_date.name = "date"
	_date.add_theme_font_override("font", Palette.display(500))
	_date.add_theme_font_size_override("font_size", 21)
	where.add_child(_date)
	row.add_child(_rule())
	# Stage S16.1: approval and political capital first on the bar and the last to give way:
	# the centre of the board is covered whenever a popup is open, and capital is what every
	# decision is paid in.
	_vital = HBoxContainer.new()
	_vital.name = "vital"
	_vital.add_theme_constant_override("separation", 0)
	row.add_child(_vital)
	_capital = _chip_button("Political capital")
	_capital.name = "capital"
	_capital.visible = false
	_capital.pressed.connect(func() -> void: open_overlay("parliament"))
	var line: HBoxContainer = _capital.get_meta("value").get_parent()
	var coin := TextureRect.new()
	coin.texture = Palette.icon("capital", 22)
	coin.custom_minimum_size = Vector2(22, 22)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.self_modulate = Palette.INK
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(coin)
	line.move_child(coin, 0)
	_vital.add_child(_capital)
	_chips_rule = _rule()
	row.add_child(_chips_rule)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 0)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.clip_contents = true
	row.add_child(_chips)
	row.add_child(_rule())
	# Stage S15.1: search and Add policy, kept with words on a narrow window too.
	search = Search.new()
	search.fitted.connect(func() -> void: _fit_bar.call_deferred())
	search.searched.connect(_searched)
	search.pointed.connect(func(result: Dictionary) -> void: board.light(str(result.get("node", ""))))
	search.picked.connect(_open_result)
	row.add_child(search)
	var add := Button.new()
	_add_button = add
	add.name = "open_add_policy"
	add.text = "Add policy"
	add.icon = Palette.icon("policy", 20)
	add.theme_type_variation = "Quiet"
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.tooltip_text = "The policies not in force, by area (A)"
	add.pressed.connect(func() -> void: open_add_policy())
	row.add_child(add)
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
		button.tooltip_text = "Run the next %s" % ["month (Space)", "three months", "twelve months"][[1, 3, 12].find(spec[1])]
		var count: int = spec[1]
		button.pressed.connect(func() -> void: advance(count))
		row.add_child(button)
		_advance.append(button)
	row.add_child(_rule())
	for spec in [["Budget", "balance", "budget"], ["Parliament", "parliament", "parliament"]]:
		var button := Button.new()
		button.text = spec[0]
		button.name = "open_" + spec[2]
		button.icon = Palette.icon(spec[1], 20)
		button.theme_type_variation = "Quiet"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var which: String = spec[2]
		button.pressed.connect(func() -> void: open_overlay(which))
		button.tooltip_text = "%s (%s)" % ["The Budget" if spec[2] == "budget" else spec[0], "B" if spec[2] == "budget" else "P"]
		button.set_meta("words", spec[0])
		row.add_child(button)
		_wide.append(button)
	# Stage S14.1: the key to the board.
	var key := Button.new()
	key.name = "open_key"
	key.text = "?"
	key.theme_type_variation = "Quiet"
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.custom_minimum_size.x = 34
	key.tooltip_text = "The key: what every shape and colour on the board means (K)"
	key.pressed.connect(show_key)
	row.add_child(key)
	_menu = MenuButton.new()
	_menu.name = "menu"
	_menu.text = "Menu"
	_menu.tooltip_text = "Save, load, sound, the size of the screen, help"
	_menu.flat = false
	_menu.theme_type_variation = "Quiet"
	_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_menu)
	_parliament_button = row.get_node("open_parliament")
	_bar.resized.connect(_fit_bar)
	resized.connect(_fit_bar)
	get_viewport().size_changed.connect(_fit_bar)
	var menu := _menu.get_popup()
	for item in [["Save", 0], ["Load", 1], ["Reload model", 2]]:
		menu.add_item(item[0], item[1])
	menu.add_separator()
	menu.add_check_item("Amounts a year", 3)
	var scales := PopupMenu.new()
	scales.name = "scale"
	scales.add_radio_check_item("Automatic", 100)
	for s in [100, 125, 150, 175, 200]:
		scales.add_radio_check_item("%d%%" % s, s + 1000)
	scales.id_pressed.connect(func(id: int) -> void: set_ui_scale(0.0 if id == 100 else (id - 1000) / 100.0))
	menu.add_submenu_node_item("Size of the screen", scales, 5)
	menu.add_check_item("Full screen    F11", 10)  # stage S18.2
	# Stage S13.6: sound on or off and its volume, kept with the screen size.
	menu.add_check_item("Sound", 7)
	var volumes := PopupMenu.new()
	volumes.name = "volume"
	for v in [25, 50, 75, 100]:
		volumes.add_radio_check_item("%d%%" % v, v)
	volumes.id_pressed.connect(func(id: int) -> void: set_volume(id / 100.0))
	menu.add_submenu_node_item("Volume", volumes, 8)
	menu.add_separator()
	menu.add_item("Show the guide again", 9)
	menu.add_item("The key", 4)
	menu.add_item("Keys", 6)
	menu.id_pressed.connect(func(id: int) -> void:
		menu_action(["save", "load", "reload", "per_year", "key", "", "help", "sound", "", "guide", "fullscreen"][id]))
	_update_menu()


## Stage S17.1: the top bar never overflows the window, and what gives way as the window
## narrows does so in a stated order, each step only when the one before was not enough:
## first the words on the Budget and Parliament buttons (their pictograms stay) and on "3
## months" and "Year" ("+3", "+12"); then the search field, to the narrower of its widths and
## then to its button (it opens to type in, and the figures give way to it while it is
## open); then the headline figures, one at a
## time, least important first: in the order of `[play] give_way`, then any it does not name
## from the right; last, on a window too narrow even then, Add policy's words (its pictogram
## stays). Approval and political capital never give way. `bar_state()` says how far it went.
func _fit_bar() -> void:
	if _fitting:
		return
	_fitting = true
	# Judged by the screen's own width, not the bar's (which grows to what it holds, so a bar
	# laid out wide could never find itself narrow again).
	var room := size.x
	var row: Control = _bar.get_child(0)
	var band := _bar.get_theme_stylebox("panel")
	room -= band.get_margin(SIDE_LEFT) + band.get_margin(SIDE_RIGHT)
	var fits := func() -> bool: return row.get_combined_minimum_size().x <= room
	_words(true)
	_add_button.text = "Add policy"
	_chips_rule.visible = true  # counted in every fit, so hiding it at the end changes no decision
	search.set_compact(false, false)
	for chip in _chips.get_children():
		(chip as Control).visible = true
	_bar_state = {"words": true, "search": true, "hidden": PackedStringArray(), "add_words": true}
	if not fits.call():
		_words(false)
		_bar_state["words"] = false
	if not fits.call():
		search.set_compact(false, true)  # the narrower of its two widths first
	if not fits.call():
		search.set_compact(true, true)
		_bar_state["search"] = not search.is_button()
	if not fits.call():
		var hidden := PackedStringArray()
		for key in _give_way():
			(_chip[key]["button"] as Control).visible = false
			hidden.append(key)
			if fits.call():
				break
		_bar_state["hidden"] = hidden
	if not fits.call():
		_add_button.text = ""
		_bar_state["add_words"] = false
	# No rule before the figures when every one of them has given way.
	_chips_rule.visible = _chips.get_children().any(func(c): return (c as Control).visible)
	# Stage S18: the row is laid out afresh after every fit. The search field grows at once
	# when it is tried at its wider sizes, and a fit that ends where it began changes no
	# least size, so nothing else would bring the field back to its button (it lay over Add
	# policy after a sheet opened: tests/bar_check.gd).
	(row as Container).queue_sort()
	_fitting = false
	_place_results.call_deferred()


## Stage S17: the month a game was loaded in (-1: not loaded, or a month has run since).
var _loaded_at := -1
var _fitting := false
var _add_button: Button
var _chips_rule: Control
var _bar_state := {"words": true, "search": true, "hidden": PackedStringArray(), "add_words": true}


## Stage S17.1: how the top bar stands: `words` (its buttons have theirs), `search` (the field
## is open, not its button), `hidden` (the headline figures that gave way, in order),
## `add_words` (Add policy has its words).
func bar_state() -> Dictionary:
	return _bar_state


func _words(on: bool) -> void:
	for button in _wide:
		button.text = str(button.get_meta("words")) if on else ""
	_advance[1].text = "3 months" if on else "+3"
	_advance[2].text = "Year" if on else "+12"


## The headline figures that may give way (every one but approval), least important first.
func _give_way() -> Array:
	var order := []
	for key in play.get("give_way", []):
		if _chip.has(str(key)) and str(key) != _approval_key() and not order.has(str(key)):
			order.append(str(key))
	var rest: Array = _chip.keys().filter(func(k): return k != _approval_key() and not order.has(k))
	rest.reverse()
	return order + rest


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
	box.add_theme_constant_override("separation", -3)  # off the scale: closes up the leading between a caption and its figure
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(box)
	var label := Label.new()
	label.text = caption.to_upper()
	label.theme_type_variation = "Heading"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
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
		button.custom_minimum_size.x = box.get_combined_minimum_size().x + 16.0)
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
	menu.set_item_checked(menu.get_item_index(7), Sound.enabled)
	menu.set_item_checked(menu.get_item_index(10), fullscreen)
	var volumes: PopupMenu = menu.get_node("volume")
	for i in volumes.item_count:
		volumes.set_item_checked(i, is_equal_approx(volumes.get_item_id(i) / 100.0, Sound.volume))
	menu.set_item_disabled(menu.get_item_index(9), not started)


## The menu's actions, by name: "save", "load", "reload", "per_year", "key", "help".
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
		"key":
			show_key()
		"help":
			_show_dialog("Keys", HELP + map_credit())
		"sound":
			Sound.enabled = not Sound.enabled
			Sound.save_settings()
			_update_menu()
		"guide":
			show_guide()
		"fullscreen":
			set_fullscreen(not fullscreen)


## Stage S18.2: the whole screen, or a window (F11, or the menu), kept with the
## other settings. With the size of the screen on Automatic, the size follows the new height.
var fullscreen := false


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
		if _scale_choice <= 0.0:
			get_tree().create_timer(0.25).timeout.connect(func() -> void: _apply_scale(0.0))
	_save_setting("ui", "fullscreen", on)
	_update_menu()


func set_volume(volume: float) -> void:
	Sound.volume = clampf(volume, 0.0, 1.0)
	Sound.enabled = true
	Sound.save_settings()
	_update_menu()
	Sound.play("open")


func _save_setting(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value(section, key, value)
	config.save(SETTINGS)


# ---------------------------------------------------------------------------- guide

## Stage S13.6: the guide comes on a player's first game, one started from the start screen
## with a display, and never for a game given with --scenario (the scripted checks).
static func should_guide(from_start_screen: bool, headless: bool, seen: bool) -> bool:
	return from_start_screen and not headless and not seen


func guide_seen() -> bool:
	var config := ConfigFile.new()
	return config.load(SETTINGS) == OK and bool(config.get_value("guide", "seen", false))


## Shows the first-minutes guide; `remember` false leaves the "seen" setting alone.
func show_guide(remember := true) -> void:
	if not started:
		return
	close_popup()
	close_overlay()
	report.dismiss()
	guide.remember = remember
	guide.begin(guide_steps())


## The guide's steps, each pointing at something on the board now; a step whose target
## the model lacks (no groups, say) is left out.
func guide_steps() -> Array:
	var steps := []
	var first := func(kind: String) -> String:
		var keys := board.keys_of(kind)
		for k in keys:
			if int(board.nodes[k]["tier"]) == 3:
				return k
		return keys[0] if not keys.is_empty() else ""
	steps.append({"title": "Your government", "target": func() -> Rect2: return _node_rect("centre"),
		"text": "Approval, the months to the election, political capital."})
	var policy: String = first.call("policy")
	if policy != "":
		steps.append({"title": "Your policies", "target": func() -> Rect2: return _node_rect(policy),
			"text": "Click one to change it."})
	var indicator: String = first.call("indicator")
	if indicator != "":
		steps.append({"title": "The country", "target": func() -> Rect2: return _node_rect(indicator),
			"text": "What you are judged by. Click one to see why it moved."})
	var group: String = first.call("group")
	if group != "":
		steps.append({"title": "The people", "target": func() -> Rect2: return _ring_rect(),
			"text": "The voters, by group. The outer edge is how many back you."})
	steps.append({"title": "Next month", "target": func() -> Rect2: return _advance[0].get_global_rect(),
		"text": "Or press Space."})
	return steps


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
	board.build(entries, play, lever_entries, _key_label, func(l: String) -> Variant: return game.latest(l), game.pending())
	politics.build_groups(board, play.get("web", {}), scenario_path.get_base_dir())
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
	_map_situations()
	_build_index()
	_country.text = str(play.get("country", game.scenario_name())).to_upper()
	_parliament_button.visible = not politics.settings.is_empty()


func _headline_keys() -> Array:
	var keys: Array = play.get("headline", [])
	if keys.is_empty():
		keys = play.get("watch", [])
	# Stage S13.7: the top bar's approval is the player's own bloc's rating when there is one.
	var support := str(play.get("politics", {}).get("support", ""))
	var approval := _approval_key()
	return keys.slice(0, 6).map(func(k: Variant) -> Variant: return approval if support != "" and str(k) == support else k)


## Stage S13.7: the approval the centre and the top bar show: the player's own bloc's rating
## when the scenario names one ([play.politics] `own`), else the governing blocs' (`support`).
func _approval_key() -> String:
	var settings: Dictionary = play.get("politics", {})
	var own := str(settings.get("own", ""))
	return own if own != "" and not _key_entry(own).is_empty() else str(settings.get("support", ""))


## A headline key is a row name, optionally with "-" in front to show it negated.
func _key_entry(key: String) -> Dictionary:
	return rows.get(key.trim_prefix("-"), {})


func _key_label(key: String) -> String:
	var labels: Dictionary = play.get("labels", {})
	if labels.has(key):
		return str(labels[key])
	var support := str(play.get("politics", {}).get("support", ""))
	if key == _approval_key() and labels.has(support):
		return str(labels[support])  # stage S13.7: the own bloc's rating keeps the name "Approval"
	return str(_key_entry(key).get("label", key))


func _build_headline() -> void:
	for child in _chips.get_children():
		child.queue_free()
	for child in _vital.get_children():
		if child != _capital:
			child.queue_free()
	_chip.clear()
	for key in _headline_keys():
		var entry := _key_entry(key)
		if entry.is_empty():
			continue
		var chip := _chip_button("Approval" if key == _approval_key() else _key_label(key))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.name = "chip_" + key
		chip.tooltip_text = str(entry.get("doc", ""))
		var row_key: String = key
		chip.pressed.connect(func() -> void: open_indicator(str(entry["name"]), row_key, chip.get_global_rect()))
		# Stage S16.1: the approval stands with the capital, first on the bar.
		if key == _approval_key():
			_vital.add_child(chip)
			_vital.move_child(chip, 0)
		else:
			_chips.add_child(chip)
		_chip[key] = {"button": chip, "entry": entry, "shown": null}
	_fit_bar.call_deferred()


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


## Stage S14.1: what an engine event changed, redrawn: the sheets only while open (they are
## refreshed when they open), the board's state without laying it out again.
func _refresh(stepped := false) -> void:
	_show_date()
	var modded := PackedStringArray()
	for mod in game.active_mods():
		modded.append(str(mod["name"]))
	_country.tooltip_text = "" if modded.is_empty() else "With " + ", ".join(modded)
	_country.text = str(play.get("country", game.scenario_name())).to_upper() + (" · WITH " + ", ".join(modded).to_upper() if not modded.is_empty() else "")
	for key in _chip:
		_show_chip(key, stepped)
	_refresh_sheets()
	var pending: Dictionary = game.pending()
	for name in _costs.keys():
		if not pending.has(name):
			_costs.erase(name)
	var capital := _show_capital()
	_show_centre(capital)
	board.refresh(latest_value, previous_value, func(l: String) -> Variant: return game.latest(l), _start_of, pending, stepped)
	strip.set_flags(_flags())
	# Stage S15.1: each situation in force flags its node.
	var flags := {}
	for entry in situations:
		var name := str(entry["name"])
		if _situations_on.get(name, false) and _situation_nodes.has(name):
			var k: String = _situation_nodes[name]
			flags[k] = Array(flags.get(k, [])) + ["good" if str(entry["situation"]) == "good" else "bad"]
	board.node_flags = flags
	_refresh_popup(pending, capital)
	_set_controls(not failed and not lost)
	_fit_bar()  # stage S17.1: the figures' widths move with their values


## The date on the top bar: the month shown and how far into the term.
func _show_date() -> void:
	var done := game.steps_done()
	_date.text = fmt.month_name(maxi(done - 1, 0)) + ("  ·  start" if done == 0 else "  ·  %d/%d" % [done, term])


## Stage S15.3: what moved each stance last: the newest bill passed among the levers its
## formula reads (from the catalogue, so no engine call).
func _stance_moves() -> void:
	var words := {}
	var changes := game.changes()
	for item in play.get("web", {}).get("stances", []):
		var row := str(item.get("row", ""))
		var entry: Dictionary = rows.get(row, {})
		var reads: PackedStringArray = entry.get("inputs", PackedStringArray())
		for i in range(changes.size() - 1, -1, -1):
			var c: Dictionary = changes[i]
			if c.get("passed", true) and reads.has(str(c["lever"])):
				var key := board.holds(str(c["lever"]))
				var label := str(board.policy_node(key).get("long_label", board.policy_node(key).get("label", c["lever"]))) if key != "" else str(c["lever"])
				words[row] = "last moved by %s, %s" % [label, fmt.month_name(int(c["step"]))]
				break
	politics.last_moved = words


## The sheets' figures (read elsewhere too, so kept up to date while shut).
func _refresh_sheets() -> void:
	_stance_moves()
	budget.refresh(func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row))
	politics.refresh(func(name: String) -> Dictionary: return game.cells(name),
		func(row: String) -> Variant: return game.latest(row), func(row: String) -> Variant: return game.previous(row),
		game.steps_done())


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
			value.text = fmt.value(entry, int(roundf(v)) if integer else v, true, false), 0.0, 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		value.text = fmt.value(entry, now, true, false)
	change.text = ""
	chip["button"].tooltip_text = str(entry.get("doc", "")) if now != null else "%s\nAwaiting the first month's figures" % str(entry.get("doc", ""))
	if now != null and before != null and typeof(now) != TYPE_BOOL and float(now) != float(before):
		var d := float(now) - float(before)
		var better := _better(key)
		change.text = "▲" if d > 0.0 else "▼"
		if key == _approval_key():  # stage S16.1: the approval says by how much
			change.text += " " + fmt.change(entry, d)
		change.add_theme_color_override("font_color", Palette.INK if better == "" else (Palette.GOOD if (d > 0.0) == (better == "high") else Palette.BAD))
		chip["button"].tooltip_text = "%s\n%s on last month" % [str(entry.get("doc", "")), fmt.change(entry, d)]


## "high" or "low" when the board says which way a row is better, "" otherwise.
func _better(key: String) -> String:
	if key == _approval_key():
		return "high"  # stage S17.1: the approval's change in the colour the centre gives it
	var node: Dictionary = board.nodes.get("indicator:" + key, {})
	return str(node.get("better", ""))


## Stage S12.5: the political capital on the top bar (with what the bills waiting will
## cost); returns it, or -1 for a model without it.
func _show_capital() -> float:
	var name := str(catalogue.get("capital", ""))
	var entry: Dictionary = entries.get(name, {})
	var now: Variant = game.latest(str(entry.get("row", name))) if name != "" else null
	if now == null:
		_capital_text = ""
		_capital.visible = false
		return -1.0
	var before: Variant = game.previous(str(entry.get("row", name)))
	var text := "Political capital %.1f" % float(now)
	if before != null and absf(float(now) - float(before)) >= 0.05:
		text += " (%+.1f)" % (float(now) - float(before))
	var waiting := 0.0
	for cost in _costs.values():
		waiting += float(cost)
	if waiting > 0.0:
		text += " · %.1f for bills waiting" % waiting
	_capital_text = text
	var value: Label = _capital.get_meta("value")
	var change: Label = _capital.get_meta("change")
	_capital.visible = true
	value.text = "%.1f" % float(now)
	# Stage S16.1: what the bills waiting will cost beside it; red, and saying so, when they
	# cannot all be paid for.
	var short := waiting > float(now) + 1e-9
	# Stage S17.1: short, the shortfall alone (the tooltip and the policy's popup have the rest):
	# both figures together pushed a headline figure off a 1920-pixel bar.
	change.text = ("%.1f short" % (waiting - float(now)) if short else "bills waiting %.1f" % waiting) if waiting > 0.0 else ""
	change.add_theme_color_override("font_color", Palette.BAD if short else Palette.PENDING)
	value.add_theme_color_override("font_color", Palette.BAD if short else Palette.INK)
	var why := "\nThe bills waiting cost %.1f more than there is: those that come last are refused." % (waiting - float(now)) if short else ""
	_capital.tooltip_text = "%s%s\n%s" % [text, why, str(entry.get("doc", ""))]
	_capital_short = short
	return float(now)


## The centre of the board: the government's approval (the own bloc's or the poll rating named in
## [play.politics]; for a model without politics, the first headline figure), the months to
## the election and the political capital.
func _show_centre(capital: float) -> void:
	var settings: Dictionary = play.get("politics", {})
	var key := _approval_key()
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
		var moved: String = fmt.change(entry, d)
		centre["change"] = ("▲ " if d > 0.0 else "▼ ") + moved if moved != "no change" else "no change on last month"
		centre["change_colour"] = (Palette.GOOD if d > 0.0 else Palette.BAD) if moved != "no change" else Palette.MUTED
	elif now == null:
		centre["change"] = "Awaiting the first month's figures"
		centre["change_colour"] = Palette.MUTED
	var months: Variant = game.latest(str(settings.get("months_to_election", "")))
	if months != null:
		centre["election"] = "Election in %d months" % int(months) if int(months) > 0 else "Election this month"
	if capital >= 0.0:
		var waiting := 0.0
		for cost in _costs.values():
			waiting += float(cost)
		centre["capital"] = "Capital %.1f%s" % [capital, (" · bills waiting %.1f" % waiting) if waiting > 0.0 else ""]
		centre["capital_colour"] = Palette.BAD if waiting > capital else (Palette.PENDING if waiting > 0.0 else Palette.INK)
	board.centre = centre


func _set_controls(enabled: bool) -> void:
	var busy := game != null and game.is_busy()
	# Stage S9.1: no month runs while a dilemma waits for an answer.
	var waiting := not unanswered_dilemmas().is_empty()
	for button in _advance:
		button.disabled = not enabled or busy or waiting
		# Stage S14.1: its own tooltip comes back once the question is answered.
		if not button.has_meta("tip"):
			button.set_meta("tip", button.tooltip_text)
		button.tooltip_text = "Answer the question put to you first" if waiting else str(button.get_meta("tip"))
	_status.text = "working…" if busy else ""
	_update_menu()


# ---------------------------------------------------------------------------- popups

## Opens the popup of a board node: "policy:<key>", "indicator:<row>", "group:<key>",
## "flag:<key>" or "centre" (Parliament).
func open_node(key: String, from := Rect2()) -> void:
	if board.available.has(key):
		_open_to_introduce(key)  # its popup, to be introduced (the sheet's own choice presets it)
		return
	if not board.nodes.has(key):
		return
	var node: Dictionary = board.nodes[key]
	var origin := _node_rect(key) if from == Rect2() else from
	match str(node["kind"]):
		"centre":
			open_overlay("parliament")
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
	report.dismiss()


func _node_rect(key: String) -> Rect2:
	var node: Dictionary = board.nodes.get(key, {})
	if node.is_empty():
		return Rect2(get_viewport_rect().size / 2.0, Vector2.ONE)
	var p: Vector2 = node["pos"] + board.position
	var r: float = node["r"]
	if str(node["kind"]) == "group":
		r = board._group_band * 0.5 + 8.0  # the arc and its approval
	var rect := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
	# Stage S14.1: with its label (and the tag it shows when selected), so a popup opens
	# beside both, not over them.
	var label: Rect2 = node.get("label_rect", Rect2())
	if label.size != Vector2.ZERO:
		rect = rect.merge(Rect2(label.position + board.position, label.size).grow(10.0))
	return rect


## Stage S16.1: the whole ring of groups on screen (the guide points at all of it).
func _ring_rect() -> Rect2:
	if board._group_ring == null:
		return _node_rect("centre")
	var r: float = board._group_ring.rx + board.ring_reach()
	return Rect2(board.position + board._c - Vector2(r, r), Vector2(r, r) * 2.0)


## Stage S14.1: a pennant on the strip: a question waiting is asked; a situation opens its
## popup, under its pennant.
func _open_flag(flag: Dictionary) -> void:
	if str(flag.get("tone", "")) == "ask":
		ask_dilemma()
	elif str(flag.get("name", "")) != "":
		open_situation(str(flag["name"]))


## Stage S15.1: a situation: its node lit, and its explanation beside the node, with what set
## it off (a link to the node's own popup). Without a node, under the strip as before.
func open_situation(name: String) -> void:
	var entry: Dictionary = entries.get(name, {})
	if entry.is_empty():
		return
	var key: String = _situation_nodes.get(name, "")
	var origin := Rect2(Vector2(get_viewport_rect().size.x - 200.0, BAR_HEIGHT + STRIP_HEIGHT), Vector2(1, 1))
	if key != "":
		origin = _node_rect(key)
		board.light(key)
	popup.open(func() -> Control: return _entry_content(name, str(entry.get("row", ""))), origin)
	_after_open()
	var card := indicator_card()
	if card != null:
		var onset := situation_onset(str(entry.get("row", "")))
		card.since = "since " + fmt.month_name(onset) if game.latest(str(entry.get("row", ""))) == true and onset >= 0 else ""
		card.refresh(latest_value, previous_value, "")
	if card != null and key != "":
		var n: Dictionary = board.nodes[key]
		card.set_off_by("%s %s" % [n["label"], n["value"]], key)


## The board key of the node a situation belongs to, or "".
func situation_node(name: String) -> String:
	return _situation_nodes.get(name, "")


## Stage S15.1: which node each situation belongs to: the catalogue's own field when it has
## one, else [play.web] `situations`, else the first value its condition reads that is on the
## board.
func _map_situations() -> void:
	_situation_nodes.clear()
	var given: Dictionary = play.get("web", {}).get("situations", {})
	var by_name := {}
	for k in board.keys_of("indicator"):
		by_name[str(board.nodes[k]["name"])] = k
	for entry in situations:
		var name := str(entry["name"])
		var key := ""
		for field in ["statistic", "set_off_by", "row_of"]:
			if key == "" and str(entry.get(field, "")) != "":
				key = _board_key_of(str(entry[field]), by_name)
		if key == "" and given.has(name):
			key = _board_key_of(str(given[name]), by_name)
		if key == "":
			for used in entry.get("inputs", PackedStringArray()):
				if by_name.has(str(used)):
					key = by_name[str(used)]
					break
		if key != "":
			_situation_nodes[name] = key


## A row or catalogue name as the key of its indicator on the board, or "".
func _board_key_of(value: String, by_name: Dictionary) -> String:
	if board.nodes.has("indicator:" + value):
		return "indicator:" + value
	return by_name.get(value, "")


## Stage S15.1: the search index: everything on the board, the policies not in force and the
## situations; each with the words it is found by.
func _build_index() -> void:
	var items := []
	var also := _also_words()
	for key in board.order:
		var n: Dictionary = board.nodes[key]
		var kind: String = {"policy": "policy", "indicator": "statistic", "group": "group"}.get(str(n["kind"]), "")
		if kind == "":
			continue
		items.append(_index_item(key, kind, n, also, key))
	for key in board.available:
		items.append(_index_item(key, "add", board.available[key], also, ""))
	# Stage S15.5: the statistics kept off the board ([play.web] `shelf`), opened as any value's.
	for item in play.get("web", {}).get("shelf", []):
		var row := str(item.get("row", ""))
		var entry: Dictionary = rows.get(row, {})
		if entry.is_empty():
			continue
		var see: String = "indicator:" + str(item.get("see", ""))
		var label := _key_label(row)
		items.append({"key": "entry:" + str(entry["name"]), "kind": "shelf", "label": label, "row": row,
			"icon": board.nodes[see]["icon"] if board.nodes.has(see) else Palette.icon("indicator"), "node": see if board.nodes.has(see) else "",
			"words": [label, " ".join(also.get(row, [])), str(entry.get("label", "")) + " " + str(entry["name"]).replace("_", " "), str(entry.get("doc", ""))]})
	for entry in situations:
		var name := str(entry["name"])
		var on_node: String = _situation_nodes.get(name, "")
		items.append({"key": "situation:" + name, "kind": "situation", "label": str(entry.get("label", name)),
			"icon": board.nodes[on_node]["icon"] if on_node != "" else Palette.icon("indicator"),
			"node": _situation_nodes.get(name, ""), "words": [str(entry.get("label", name)), " ".join(also.get(name, [])), name.replace("_", " "), str(entry.get("doc", ""))]})
	search.set_index(items)


func _index_item(key: String, kind: String, n: Dictionary, also: Dictionary, node: String) -> Dictionary:
	var words := PackedStringArray()
	for lever in n.get("levers", PackedStringArray()):
		words.append(str(lever).replace("_", " "))
		words.append(str(entries.get(lever, {}).get("label", "")))
	var name := str(n.get("name", ""))
	words.append(name.replace("_", " "))
	words.append(str(n.get("long_label", "")))
	var other := PackedStringArray()
	for k in [key, key.get_slice(":", 1), name, str(n.get("row", ""))]:
		for w in also.get(k, []):
			other.append(str(w))
	return {"key": key, "kind": kind, "label": str(n["label"]), "icon": n["icon"], "node": node,
		"words": [str(n["label"]), " ".join(other), " ".join(words), str(n.get("doc", ""))]}


## Stage S15.1: `also = [...]` wherever a [play.web] entry gives it (an area's policies and
## indicators, the groups), by its key, row and levers; and [play.web] `also` = { name =
## [...] } for anything else (a situation, say).
func _also_words() -> Dictionary:
	var out := {}
	var web: Dictionary = play.get("web", {})
	var take := func(item: Dictionary) -> void:
		if not item.has("also"):
			return
		for k in [item.get("key", ""), item.get("row", "")] + Array(item.get("levers", [])):
			if str(k) != "":
				out[str(k)] = Array(out.get(str(k), [])) + Array(item["also"])
	for area in web.get("areas", []):
		for list in [area.get("policies", []), area.get("indicators", [])]:
			for item in list:
				take.call(item)
	for g in web.get("groups", []):
		take.call(g)
	var extra: Dictionary = web.get("also", {}) if web.get("also", {}) is Dictionary else {}
	for k in extra:
		out[str(k)] = Array(out.get(str(k), [])) + Array(extra[k])
	return out


## The search's matches: the board dims to their nodes (a situation's, its node).
func _searched(found: Array) -> void:
	var keys := []
	for r in found:
		if str(r.get("node", "")) != "":
			keys.append(str(r["node"]))
	board.set_search(keys, search.text.strip_edges() != "")
	_place_results()
	_place_results.call_deferred()  # again once the bar has made room for the field
	if found.is_empty():
		board.light("")


## Stage S17.1: the search's list hangs under the top bar (not under the field, where the bar
## cut off its top), its left edge on the field's, and inside the window. The field moves
## when it opens from its button, so the list is placed again whenever the bar fits itself.
func _place_results() -> void:
	if search == null or search.results == null:
		return
	var wide: float = search.results.get_combined_minimum_size().x
	var x := minf(search.get_global_rect().position.x, size.x - wide - 8.0)
	search.results.position = Vector2(maxf(x, 8.0), BAR_HEIGHT + 4.0)


## A result chosen: its popup, a situation's explanation, or the Add policy sheet at it.
func _open_result(result: Dictionary) -> void:
	var key := str(result["key"])
	search.results.visible = false
	search.release_focus()
	match str(result["kind"]):
		"situation":
			open_situation(key.trim_prefix("situation:"))
		"add":
			open_add_policy(key)
		"shelf":
			open_indicator(key.trim_prefix("entry:"), str(result.get("row", "")))
		_:
			board.light(key)
			open_node(key)


## For the checks: types into the search field, as a player would after "/".
func search_for(words: String) -> Array:
	search.grab_focus()
	search.type_query(words)
	return search.found


## Stage S14.1: the key, on a sheet of its own.
func show_key() -> void:
	close_popup()
	if _key_sheet == null:
		_key_sheet = _new_sheet("The key", 760.0)
		_key_sheet.name = "key_sheet"
		var page := KeyPage.new()
		page.name = "key_page"
		_key_sheet.body.add_child(page)
		page.build(board)
	for sheet in [_budget_sheet, _parliament_sheet]:
		sheet.close()
	_key_sheet.open()
	_update_input()


func _node_content(key: String) -> Control:
	var node: Dictionary = board.policy_node(key) if board.policy_node(key).size() > 0 else board.nodes[key]
	if node["kind"] == "policy":
		var card := LeverPanel.new()
		card.fmt = fmt
		card.name = "policy_card"
		# Stage S13.5: a policy not in force opens to be introduced; one that can be ended
		# offers its repeal.
		card.introducing = board.available.has(key)
		card.off_stored = node.get("off_stored") if not node.get("ghost", false) else null
		var lever_entries := []
		for lever in node["levers"]:
			lever_entries.append(entries[lever])
		card.build(node, lever_entries, bool(catalogue.get("legislature", false)), _start_of)
		card.lever_changed.connect(func(name: String, raw: String) -> void:
			_lever_typed(name, raw)
			if card.introducing and game.pending().has(name):
				close_popup())
		card.draft_changed.connect(func(_name: String, _raw: String) -> void:
			_refresh_popup(game.pending(), _show_capital())
			_forecast_timer.start())
		card.repeal_pressed.connect(func(name: String) -> void: _lever_typed(name, _typed_off(key)))
		card.lever_cancelled.connect(func(name: String) -> void:
			game.cancel_lever(name)
			Sound.play("withdraw")
			_refresh())
		card.follow.connect(func(name: String) -> void: _follow(name))
		card.more_toggled.connect(popup.relayout)
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
	# Stage S15.5: a statistic off the board takes the pictogram of the one that stands for it.
	for item in play.get("web", {}).get("shelf", []):
		if node.is_empty() and str(item.get("row", "")) == row_key.trim_prefix("-") and board.nodes.has("indicator:" + str(item.get("see", ""))):
			icon = board.nodes["indicator:" + str(item["see"])]["icon"]
	card.build(name, row_key, entry, label, str(node.get("area", "")), icon, entries, play, _breakdowns_of(name), compare, movers)
	card.follow.connect(func(target: String) -> void: _follow(target))
	# Stage S15.5: the statistics off the board that this one stands for.
	var see_also := []
	for item in play.get("web", {}).get("shelf", []):
		if str(item.get("see", "")) == row_key.trim_prefix("-") and rows.has(str(item.get("row", ""))):
			see_also.append([_key_label(str(item["row"])), str(rows[str(item["row"])]["name"])])
	card.set_see_also(see_also)
	if card.trace == null:
		return card  # stage S15.1: a situation's popup has no trace
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


## Stage S15.1: the Add policy sheet: every area with what it has to add, each policy with
## its line, the smallest step's cost and vote, and who would cheer and boo; opened at `key`'s
## area (a policy not in force) or the first area with something to add.
func open_add_policy(key := "") -> void:
	close_popup()
	report.dismiss()
	for sheet in [_budget_sheet, _parliament_sheet, _key_sheet]:
		if sheet != null:
			sheet.close()
	if _add_sheet != null and is_instance_valid(_add_sheet):
		_add_sheet.queue_free()
	_add_sheet = _new_sheet("Add policy", 900.0)
	_add_sheet.name = "add_policy_sheet"
	add_list = AddPolicy.new()
	add_list.name = "add_policy"
	_add_sheet.body.add_child(add_list)
	var areas := []
	var by_area := {}
	for a in board.areas:
		areas.append([str(a["name"]), Palette.icon(str(a.get("icon", "policy")), 22)])
		var list := []
		for k in board.available_in(str(a["name"])):
			list.append(_add_item(k))
		by_area[str(a["name"])] = list
	add_list.build(areas, by_area)
	add_list.fit(get_viewport_rect().size.y - BAR_HEIGHT - 260.0)
	add_list.chosen.connect(func(k: String) -> void:
		_add_sheet.close()
		_open_to_introduce(k, true))
	_add_sheet.open()
	if key != "":
		add_list.show_policy(key)
	_update_input()


## Which sheet is open: true while the Add policy sheet is.
func add_sheet_open() -> bool:
	return _add_sheet != null and is_instance_valid(_add_sheet) and _add_sheet.visible


## One policy not in force, as the sheet lists it.
func _add_item(key: String) -> Dictionary:
	var node: Dictionary = board.available[key]
	var lever: String = node["levers"][0]
	var raw := _first_step(key)
	var cost: float = game.bill_cost(lever, raw)
	var line := str(node.get("line", ""))
	if line == "":
		line = str(entries.get(lever, {}).get("doc", "")).get_slice(".", 0) + "."
	var item := {"key": key, "label": node["label"], "icon": node["icon"], "line": line,
		"cost": _cost_words(cost)}
	var preview: Dictionary = game.vote_preview(lever, _raw_value(raw))
	if preview.get("bill", false):
		item["passes"] = bool(preview.get("passes", true)) and bool(preview.get("affordable", true))
		var votes := int(preview.get("votes_for", 0))
		item["vote"] = ("Would pass, %d to %d" if preview.get("passes", false) else "Would be voted down, %d to %d") % [votes, int(preview.get("seats", 0)) - votes]
		if not preview.get("affordable", true):
			item["vote"] += "; not enough capital"
	# Who would cheer and who would boo: the groups the effects table has it move most, read
	# for the first step in (the table nudges up; a policy whose first step is down reads the
	# other way).
	var table: Dictionary = board.effects.get(lever, {})
	if table.is_empty():
		item["pending"] = effects_running
	else:
		var off := float(node.get("off_stored", 0.0))
		var stored := float(raw) * (fmt.minor if entries.get(lever, {}).get("money", false) else 1)
		var way := 1.0 if stored >= off else -1.0
		var moves := []
		for g in board.keys_of("group"):
			var row := str(board.nodes[g]["row"])
			if table.has(row) and absf(float(table[row])) >= 0.0005:
				moves.append([float(table[row]) * way, str(board.nodes[g]["label"])])
		moves.sort_custom(func(x, y): return x[0] > y[0])
		item["cheer"] = moves.filter(func(m): return m[0] > 0.0).slice(0, 3).map(func(m): return m[1])
		var down := moves.filter(func(m): return m[0] < 0.0)
		down.reverse()
		item["boo"] = down.slice(0, 3).map(func(m): return m[1])
	return item


## Stage S16.1: a bill's cost on the Add policy sheet, with the capital it would leave:
## "Costs 11.0 capital" over "56.7 of 67.7 left" (after the bills already waiting).
func _cost_words(cost: float) -> String:
	if cost < 0.0:
		return ""
	var capital := _show_capital()
	if capital < 0.0:
		return "Costs %.1f political capital" % cost
	var waiting := 0.0
	for c in _costs.values():
		waiting += maxf(float(c), 0.0)
	var left := capital - waiting - cost
	return "Costs %.1f capital\n%.1f of %.1f left" % [cost, left, capital] if left >= 0.0 else "Costs %.1f capital\n%.1f more than there is" % [cost, -left]


## A raw setting as typed (a string) as the bridge's previews take it.
static func _raw_value(raw: String) -> Variant:
	return int(raw) if raw.is_valid_int() else float(raw)


## Opens a policy not in force in its popup, ready to be introduced; from the Add policy sheet
## (`preset`), at the smallest step in, its cost, vote and year ahead shown.
func _open_to_introduce(key: String, preset := false) -> void:
	if not board.available.has(key):
		return
	var origin := Rect2(get_viewport_rect().size / 2.0, Vector2.ONE)
	if popup.is_open():
		popup.push(func() -> Control: return _node_content(key))
	else:
		popup.open(func() -> Control: return _node_content(key), origin)
	var card := policy_card()
	if preset and card != null and not card.levers.is_empty():
		card.preset(card.levers[0], _first_step(key))
	_after_open()


## A policy's `off` setting as a person types it (the raw a bill takes).
func _typed_off(key: String) -> String:
	var node: Dictionary = board.policy_node(key)
	return _raw(str(node["levers"][0]), float(node.get("off", 0.0)))


## A typed value as a bill takes it: a whole number for a whole-number lever.
func _raw(lever: String, typed: float) -> String:
	var entry: Dictionary = entries.get(lever, {})
	if str(entry.get("type", "")) == "int" and not entry.get("money", false):
		return "%d" % int(roundf(typed))
	return String.num(typed, 6)


## The smallest step into force from a policy's `off` setting, as typed: a level policy's
## next level; otherwise a tenth of its range.
func _first_step(key: String) -> String:
	var node: Dictionary = board.policy_node(key)
	var entry: Dictionary = entries.get(node["levers"][0], {})
	var off := float(node.get("off_stored", 0.0))
	var lo := float(entry.get("min", 0.0))
	var hi := float(entry.get("max", 1.0))
	var step := 1.0 if entry.has("levels") else (hi - lo) / 10.0
	var to := off + step if off + step <= hi else off - step
	var money: bool = entry.get("money", false)
	return _raw(str(node["levers"][0]), to / fmt.minor if money else to)


## The value of a stored lever setting as a bill or a look-ahead takes it.
func _typed_value(lever: String, stored: Variant) -> Variant:
	var entry: Dictionary = entries.get(lever, {})
	if entry.get("money", false):
		return float(stored) / fmt.minor
	return int(roundf(float(stored))) if str(entry.get("type", "")) == "int" else stored


## Stage S13.5, for the checks and keyboard play: the policies of an area not in force.
func available_policies(area: String) -> PackedStringArray:
	return board.available_in(area)


## Opens the Add policy sheet at an area (stage S15.1; the area's list was a popup before).
func open_introduce(area: String) -> void:
	open_add_policy()
	add_list.show_area(area)


## Introduces a policy not in force at `value` (in its lever's own terms, as type_lever
## takes it), as a player would: its popup, the setting picked, "Put to the Commons".
## Returns the setting's draft as a bill would take it, or "" if nothing was put forward.
func introduce_policy(key: String, value: float) -> String:
	if not board.available.has(key):
		push_error("%s is not available to introduce" % key)
		return ""
	_open_to_introduce(key)
	var card := policy_card()
	var lever: String = card.levers[0]
	card.type_value(lever, value)
	if not card.draft.has(lever):
		return ""
	var raw := str(card.draft[lever][0])
	card.put_button.pressed.emit()
	return raw


## Repeals a policy in force, as a player would, through its popup's Repeal button.
func repeal_policy(key: String) -> void:
	open_node(key)
	var card := policy_card()
	if card == null or card.repeal_button == null:
		push_error("%s cannot be repealed" % key)
		return
	card.repeal_button.pressed.emit()


## Stage S13.4: an interest group's popup, and a request for eight of its households.
func _group_content(key: String) -> Control:
	var node: Dictionary = board.nodes[key]
	var card := GroupCard.new()
	card.fmt = fmt
	card.name = "group_card"
	card.index = _group_index(node)
	var movers := []
	for m in board.movers(key):
		movers.append([m[0], board.nodes[m[0]]["label"], m[1], m[2]])
	card.build(node, entries.get(node["name"], {}), _group_drivers(), movers)
	card.set_stance(_stance_words(key))
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


## Stage S15.3: for a belief group (an end of one of [play.web] `stances`), the stance its
## "Where the government stands" reads and where the government stands on it; else "".
func _stance_words(key: String) -> String:
	var group := key.trim_prefix("group:")
	for item in play.get("web", {}).get("stances", []):
		var end := "high" if str(item.get("high_group", "")) == group else ("low" if str(item.get("low_group", "")) == group else "")
		if end == "":
			continue
		var v: Variant = game.latest(str(item.get("row", "")))
		var value := float(v) if v != null else 0.0
		var toward := str(item.get("high" if value > 0.0 else "low", "")).to_lower()
		var where := "where it stood in 2024" if absf(value) < 0.05 else "%.1f toward %s" % [absf(value), toward]
		return "Where the government stands, for them: %s, %s (they want %s)." % [str(item.get("label", "")), where, str(item.get(end, "")).to_lower()]
	return ""


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
	if card != null and not card.levers.is_empty():
		# Stage S13.5: the setting picked for a policy being introduced, or its repeal: what
		# the bill would cost and the vote it would get.
		var lever: String = card.levers[0]
		var waiting_else := capital - _waiting_except(lever)
		if card.introducing:
			card.draft_cost = game.bill_cost(lever, str(card.draft[lever][0])) if card.draft.has(lever) else -1.0
			if card.draft.has(lever) and game.has_method("vote_preview"):
				card.show_vote(lever, game.call("vote_preview", lever, _typed_value(lever, card.draft[lever][1])), waiting_else)
			elif card._rows.has(lever):
				card._rows[lever]["vote"].visible = false
		elif card.off_stored != null and game.has_method("vote_preview"):
			card.show_repeal(game.bill_cost(lever, _typed_off(card.key)), game.call("vote_preview", lever, _typed_value(lever, card.off_stored)), waiting_else)
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
		group.set_stance(_stance_words(group.key))
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
	for other in [_budget_sheet, _parliament_sheet, _key_sheet, _add_sheet if _add_sheet != null and is_instance_valid(_add_sheet) else null]:
		if other != null and other != sheet:
			other.close()
	report.dismiss()
	sheet.open()
	_refresh()
	_update_input()


func close_overlay() -> void:
	for sheet in [_budget_sheet, _parliament_sheet]:
		sheet.close()
	if add_sheet_open():
		_add_sheet.close()
	_update_input()


## Which sheet is open: "budget", "parliament" or "".
func overlay_open() -> String:
	if _budget_sheet.visible:
		return "budget"
	if _parliament_sheet.visible:
		return "parliament"
	if add_sheet_open():
		return "add_policy"  # stage S15.1
	return ""


func _update_input() -> void:
	var covered: bool = popup.is_open()
	for sheet in _sheets.get_children():
		covered = covered or (sheet as Control).visible
	board.input_enabled = not covered
	if covered:
		board.set_hover("")


func _unhandled_input(event: InputEvent) -> void:
	if guide != null and guide.visible:
		return
	# Stage S13.6: Space or Enter for next month (a focused field keeps its keys; not while
	# a question waits); B the Budget, P Parliament, K the key.
	if event is InputEventKey and event.pressed and event.keycode == KEY_F and event.ctrl_pressed and started:
		search.grab_focus()
		search.select_all()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and started \
			and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed) \
			and not get_viewport().gui_get_focus_owner() is LineEdit:
		var handled := true
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if dilemma_title() == "" and can_advance():
					advance(1)
			KEY_B:
				if overlay_open() == "budget":
					close_overlay()
				else:
					open_overlay("budget")
			KEY_P:
				if overlay_open() == "parliament":
					close_overlay()
				else:
					open_overlay("parliament")
			KEY_A:
				if add_sheet_open():
					_add_sheet.close()
				else:
					open_add_policy()
			KEY_SLASH:
				search.grab_focus()
				search.select_all()
			KEY_K:
				if _key_sheet != null and _key_sheet.visible:
					_key_sheet.close()
				else:
					show_key()
			KEY_F11:
				set_fullscreen(not fullscreen)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if popup.is_open():
			close_popup()
		elif report.visible:
			report.dismiss()
		else:
			for i in range(_sheets.get_child_count() - 1, -1, -1):
				var sheet: Sheet = _sheets.get_child(i)
				if sheet.visible and sheet.closable:
					sheet.close()
					break
		get_viewport().set_input_as_handled()


## Stage S18.3: the plate at the head of a sheet: the scenario's own for `name` (`[play.plates]`:
## a pictogram's name, or {icon, tone, beside}), else one of `icon` in `tone`.
## Stage S18.4: the acknowledgement the scenario's map of the country asks for (the file's
## own `attribution`), for the foot of How to play; "" where there is no map.
func map_credit() -> String:
	if politics == null or politics.place_map == null or not politics.place_map.visible or politics.place_map.source == "":
		return ""
	return "\n[color=#505a66]The map of the country. %s[/color]" % politics.place_map.source


func plate_for(name: String, icon: String, tone: String) -> Control:
	var plates: Dictionary = play.get("plates", {})
	return Plate.from(plates.get(name), icon, tone)


func _show_dialog(title: String, bbcode: String, plate: Control = null) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = _new_sheet(title, 720.0)
	if plate != null:
		_dialog.body.add_child(plate)
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
	if failed or lost:
		return
	if game.is_busy():
		# Stage S14.1: the engine is finishing something (copying the game for the effects
		# table, say): the months run as soon as it is free, never dropped.
		_queued = months
		return
	if not unanswered_dilemmas().is_empty():
		ask_dilemma()
		return
	# Stage S14.1: the engine is asked at once; the popup and the report close while it works.
	_snapshot_for_report()
	game.advance(months)
	close_popup()
	report.dismiss()
	strip.hide_line()
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
	Sound.play("bill" if refused == "" else "notice")
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
	if card.introducing:
		# Stage S13.5: the setting picked, against the year as it stands.
		for lever in card.draft:
			changes[lever] = _typed_value(lever, card.draft[lever][1])
		if changes.is_empty():
			card.hide_year()
		elif game.call("request_forecast", changes, 12, card.key):
			card.show_year({}, [], true)
		return
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


## Stage S13.5: "In a year"'s heading in the policy's own words: "at £2,500 a car",
## "repealed"; "" for a policy of several levers (the general heading).
func _year_heading(card: LeverPanel) -> String:
	if card.levers.size() != 1:
		return ""
	var lever: String = card.levers[0]
	var entry: Dictionary = entries.get(lever, {})
	if card.introducing:
		return "at " + fmt.value(entry, card.draft[lever][1], false, false) if card.draft.has(lever) else ""
	var pending: Dictionary = game.pending()
	if not pending.has(lever):
		return ""
	if Web.is_off(board.policy_node(card.key), pending[lever]):
		return "repealed"
	return "at " + fmt.value(entry, pending[lever], false, false)


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
## for after a game opens and after each month. Stage S14.4: the board keeps showing the last
## table's links while the new one comes in, lever by lever.
func _want_effects() -> void:
	if not game.has_method("request_effects"):
		return
	_effects_timer.start()


## True from asking for the effects table until its last lever is in (or it went stale).
var effects_running := false
## Stage S14.4: the levers measured since this month began (or the game was loaded), and how
## many times the table was asked for (for the checks: a loaded table is never asked again).
var _measured := {}
var effects_requests := 0


func _request_effects() -> void:
	if not started or game.is_busy() or failed:
		_effects_timer.start()
		return
	_ask_effects(_focus_levers())


## Asks for the levers not yet measured this month, those of `first` first (stage S14.3's
## request_effects_first).
func _ask_effects(first: PackedStringArray) -> void:
	var levers := PackedStringArray()
	# Stage S15.1: the policies not in force too, for who would cheer and boo at them.
	var all := board_levers()
	for key in board.available:
		all.append(board.available[key]["levers"][0])
	for lever in all:
		if not _measured.has(lever):
			levers.append(lever)
	if levers.is_empty():
		return  # all in (a loaded game's saved table, say): nothing to ask
	effects_requests += 1
	effects_running = game.request_effects_first(first, levers, 12)
	board.measuring = effects_running


## The levers of the policy under the pointer or open in a popup, to be measured first.
func _focus_levers() -> PackedStringArray:
	var key := board.focus_key()
	var card := policy_card()
	if card != null:
		return card.levers
	if key.begins_with("policy:") and board.nodes.has(key):
		return board.nodes[key]["levers"]
	return PackedStringArray()


## Stage S14.4: the pointer rests on a policy not yet measured while the table runs: it is
## measured next (the rest of the table follows).
func _hover_first() -> void:
	var first := _focus_levers()
	if effects_running and not first.is_empty() and not _measured.has(first[0]):
		_ask_effects(first)


## An effects event: each row's change, as a share of where it would be otherwise (for a
## rate, ten times the change in points), signed.
func _take_effects(event: Dictionary) -> void:
	var lever := str(event.get("lever", ""))
	if lever != "":
		_measured[lever] = true
		effects_running = true  # stage S14.4: a table the bridge restarted itself (a lever set)
		board.measuring = true
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


## Stage S14.1: a notice, on the line under the date: gone after a few seconds, or, for a
## problem, when clicked (a longer one opens whole).
func _show_message(bbcode: String, problem := false) -> void:
	strip.show_line(bbcode, problem, 0.0 if problem else 6.0)


func notice_visible() -> bool:
	return strip.line_visible()


func notice_text() -> String:
	return strip.line_text


func capital_text() -> String:
	return _capital_text


func title_text() -> String:
	return _country.text + " · " + _date.text


func flag_text(key: String) -> String:
	return strip.flag_text(key)


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
	_show_dialog("End of term", "\n".join(lines), plate_for("term", "laurels", "sage"))


# ---------------------------------------------------------------------------- events

## Stage S5.5: true once the player's bloc is out of government.
func _player_lost() -> bool:
	var name := str(play.get("politics", {}).get("player", ""))
	return name != "" and game.latest(name) == false


## Stage S5.5: election night. The results, and the end of the game if the player lost.
## Stage S17: a run of months ("3 months", "Year") arrives as one event, so an election in any
## of its months counts, not only one in its last: a year run across an election the player
## lost used to pass it by, and left the player governing.
func _announce_election() -> void:
	var settings: Dictionary = play.get("politics", {})
	if settings.is_empty():
		return
	var row := str(settings.get("election", ""))
	var held: bool = game.latest(row) == true
	if not held and row != "":
		var run: int = game.steps_done() - int(_report_from.get("step", game.steps_done() - 1))
		var series: PackedFloat64Array = game.series(row)
		for i in range(maxi(0, series.size() - run), series.size()):
			held = held or series[i] >= 0.5
	if not held:
		return
	lost = _player_lost()
	if lost:
		strip.show_line("You lost the election: the game is over. Load a save from the menu to play on.", true, 0.0)
	Sound.play("election")
	_show_dialog("Election night" if not lost else "Election night: you have lost office",
		politics.election_report(func(name: String) -> Dictionary: return game.cells(name), not lost),
		plate_for("election_lost" if lost else "election", "vote", "brick" if lost else "blue"))


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
	if waiting.is_empty() or lost:  # no question is put to a government out of office
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
	sheet.body.add_child(plate_for(name, "podium", "ochre"))  # stage S18.3
	sheet.body.add_child(Palette.caps("A question for the government"))
	var lines := PackedStringArray()
	if str(d.get("doc", "")) != "":
		lines.append(str(d["doc"]) + ".\n")
	for option in d.get("options", []):
		var line := "[b]%s[/b]" % str(option.get("label", option["name"]))
		if str(option.get("doc", "")) != "":
			line += ": " + str(option["doc"])
		lines.append(line + ".\n")
	sheet.add_text("\n".join(lines))
	var options: Array = d.get("options", [])
	for i in options.size():
		var answer := i + 1
		sheet.add_action(str(options[i].get("label", options[i]["name"])), func() -> void: answer_dilemma(name, answer), false)
	sheet.open()
	Sound.play("question")
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


## Stage S7.3: which situations are on now. Stage S14.1: what began or ended is told once,
## in the month's report.
func _note_situations() -> void:
	for entry in situations:
		_situations_on[str(entry["name"])] = game.latest(str(entry["row"])) == true


## Stage S13.6: where the board stood before the months a report will cover.
func _snapshot_for_report() -> void:
	var values := {}
	for key in Array(board.keys_of("indicator")) + Array(board.keys_of("group")):
		values[key] = latest_value(str(board.nodes[key]["row"]))
	# Stage S13.5: where each lever stood, so a bill that passed can be told as an
	# introduction or a repeal.
	var levers := {}
	for lever in board_levers():
		levers[lever] = game.latest(lever)
	for key in board.available:
		for lever in board.available[key]["levers"]:
			levers[lever] = game.latest(lever)
	_report_from = {"step": game.steps_done(), "changes": game.changes().size(), "values": values,
		"situations": _situations_on.duplicate(), "levers": levers}


## Stage S13.6: the month's report: the bills put to the Commons, the figures that moved
## most against their own usual movement, the situations that began or ended.
func _build_report() -> void:
	var from: Dictionary = _report_from
	_report_from = {}
	var months := game.steps_done() - int(from["step"])
	if months <= 0:
		return
	var bills := []
	var decisions := []
	var changes := game.changes()
	for i in range(int(from["changes"]), changes.size()):
		var c: Dictionary = changes[i]
		var lever := str(c["lever"])
		var key := board.holds(lever)
		var passed: bool = c.get("passed", true)
		if key == "" and passed:
			# Stage S14.1: an answer to a question, told among the decisions.
			for d in dilemmas:
				var options: Array = d.get("options", [])
				if str(d["name"]) == lever and int(c["value"]) >= 1 and int(c["value"]) <= options.size():
					decisions.append({"text": "%s: %s" % [str(d.get("label", lever)), str(options[int(c["value"]) - 1].get("label", ""))], "tone": "plain", "key": ""})
			continue
		var was: Variant = from.get("levers", {}).get(lever, game.latest(lever)) if passed else game.latest(lever)
		var what := _bill_words(lever, c["value"], was, passed and not c.get("refused", false))
		# A line opens the policy's popup while it is on the board, else its area's list.
		if not board.nodes.has(key):
			key = "add:" + key if key != "" and board.available.has(key) else ""
		if c.get("refused", false):
			bills.append({"text": "%s: refused, it needed %.1f political capital" % [what, float(c["cost"])], "tone": "notice", "key": key})
		elif not passed:
			bills.append({"text": "%s: voted down, %d to %d" % [what, int(c["votes_for"]), int(c["seats"]) - int(c["votes_for"])], "tone": "notice", "key": key})
		elif what.contains(" introduced") or what.ends_with(" repealed"):
			bills.append({"text": what, "tone": "good" if what.contains(" introduced") else "plain", "key": key})
		else:
			bills.append({"text": "%s: passed" % what, "tone": "plain", "key": key})
	if int(from["step"]) == 0 and bills.is_empty() and decisions.is_empty():
		return  # the base month: nothing before it to compare with, and nothing put forward
	var moves := []
	var values: Dictionary = from["values"]
	for key in values:
		var node: Dictionary = board.nodes.get(key, {})
		var before: Variant = values[key]
		var now: Variant = latest_value(str(node.get("row", ""))) if not node.is_empty() else null
		if before == null or now == null or typeof(now) == TYPE_BOOL:
			continue
		var entry: Dictionary = entries.get(node["name"], {})
		var d := float(now) - float(before)
		var shown: String = fmt.change(entry, d)
		if shown == "no change":
			continue
		# How unusual the move is: against the row's own mean monthly move before these months
		# (over as many months as there are), and never less than a small floor.
		var usual := _usual_move(str(node["row"]), months)
		var least := 0.0005 if fmt.is_rate(entry) else absf(float(before)) * 0.001
		var score := absf(d) / maxf(usual * sqrt(float(months)), maxf(least, 1e-12))
		var better := str(node.get("better", ""))
		var tone := "plain" if better == "" else ("good" if (d > 0.0) == (better == "high") else "bad")
		var label := str(node["label"]) + (": approval" if node["kind"] == "group" else "")
		moves.append([score, {"text": "%s  %s %s" % [label, "▲" if d > 0.0 else "▼", shown], "tone": tone, "key": key}])
	moves.sort_custom(func(a, b): return a[0] > b[0])
	var sits := []
	var was_on: Dictionary = from["situations"]
	for entry in situations:
		var name := str(entry["name"])
		var now: bool = _situations_on.get(name, false)
		if now == bool(was_on.get(name, false)):
			continue
		sits.append({"text": "%s %s" % [str(entry.get("label", name)), "began" if now else "is over"],
			"tone": ("good" if str(entry["situation"]) == "good" else "bad") if now else "plain",
			"key": "situation:" + name})
	# Stage S14.1: an election in these months, which opens Parliament.
	var elections := []
	var settings: Dictionary = play.get("politics", {})
	var held: PackedFloat64Array = game.series(str(settings.get("election", ""))) if str(settings.get("election", "")) != "" else PackedFloat64Array()
	for i in range(maxi(0, held.size() - months), held.size()):
		if held[i] >= 0.5:
			elections.append({"text": "The general election: the results", "tone": "plain", "key": "election"})
			break
	var last := game.steps_done() - 1
	var heading := fmt.month_name(last) if months == 1 else "%s to %s" % [fmt.month_name(int(from["step"]), true), fmt.month_name(last, true)]
	var top: Array = moves.slice(0, 4).map(func(m): return m[1])
	report.set_report(heading, [["Bills", bills], ["Situations", sits], ["Election", elections], ["Decisions", decisions], ["Moved most", top]])
	# Stage S14.1: the report opens only when the months have something to tell; an ordinary
	# month is one line under the date.
	if not (bills.is_empty() and sits.is_empty() and elections.is_empty() and decisions.is_empty()):
		report.reopen()
		# A bill voted down or refused sounds a notice (the report's own lines say which).
		var setback: bool = bills.any(func(b): return str(b["text"]).contains(": voted down") or str(b["text"]).contains(": refused"))
		Sound.play("notice" if setback else "month")
	else:
		Sound.play("month")
		var said := top.slice(0, 2).map(func(m): return str(m["text"]).replace("  ", " "))
		strip.show_line("%s: %s" % [heading, ", ".join(said) if not said.is_empty() else "a quiet month"], false, 3.0)


## Stage S13.5: a bill in words: "Fuel duty to 62.95p a litre"; for a policy with an `off`
## setting, "Electric car grant introduced at £2,500 a car" or "Electric car grant repealed"
## once passed (`done`), "Electric car grant, to be introduced at £2,500 a car" before. `was`
## is the lever's setting before the bill.
func _bill_words(lever: String, value: Variant, was: Variant, done: bool) -> String:
	var entry: Dictionary = entries.get(lever, {})
	var label := str(entry.get("label", lever))
	var node: Dictionary = board.policy_node(board.holds(lever))
	if not node.is_empty():
		if (node["levers"] as PackedStringArray).size() == 1:
			label = str(node["label"])
		if Web.is_off(node, value):
			return label + (" repealed" if done else ", to be repealed")
		if Web.is_off(node, was):
			return "%s%s %s" % [label, " introduced at" if done else ", to be introduced at", fmt.value(entry, value, false, false)]
	return "%s to %s" % [label, fmt.value(entry, value, false, false)]


## A row's mean monthly move over up to two years before the last `months` months, or 0
## when there is too little history.
func _usual_move(row: String, months: int) -> float:
	var values: PackedFloat64Array = game.series(row.trim_prefix("-"))
	var end := values.size() - months
	var total := 0.0
	var count := 0
	for i in range(maxi(1, end - 24), end):
		total += absf(values[i] - values[i - 1])
		count += 1
	return total / count if count >= 2 else 0.0


## Stage S14.1: an engine event redraws only what it changed: a month refreshes the screen
## (while a run of months goes on, only the date follows it, and the rest once it ends); the
## effects table, a forecast, an explanation or households touch only their own panel.
func _process(_delta: float) -> void:
	if game == null or not started:
		return
	var events := game.poll()
	var whole := false
	if _queued > 0 and not game.is_busy():
		var months := _queued
		_queued = 0
		advance(months)
	for event in events:
		match str(event.get("kind", event.get("type", ""))):
			"stepped":
				_stepped_waiting = true
				_measured.clear()  # the new month's table is to come; the last one's links stay shown
				effects_running = false
				_announce_election()
				ask_dilemma.call_deferred()
				if game.steps_done() >= term and not term_announced:
					_announce_term.call_deferred()
			"failed":
				failed = true
				whole = true
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
						var rows_ahead: Dictionary = event.get("rows", {})
						if card.introducing:
							# The forecast's "changed" side is the policy introduced here.
							var swapped := {}
							for row in rows_ahead:
								var pair: Variant = rows_ahead[row]
								swapped[row] = [pair[1], pair[0]] if pair is Array and pair.size() == 2 else pair
							rows_ahead = swapped
						card.show_year(rows_ahead, _year_rows(), false, _year_heading(card))
					popup.relayout()
			"effects":
				_take_effects(event)
			"records":
				var group := group_card()
				if group != null and str(event.get("tag", "")) == group.key:
					# Stage S17: a saved game does not keep the households' own figures for the month it
					# was saved in, so none come back until a month has run: said as it is.
					if _loaded_at == game.steps_done():
						group.none_found = "Their households show again once a month has run: a loaded game has none of this month's figures for them."
					group.show_households(event.get("records", []), play.get("web", {}).get("household", {}), _household_words())
					popup.relayout()
			"effects_done":
				effects_running = false
				board.measuring = false
				board.queue_layers()
			"saved":
				if event["error"] != "":
					_show_message("[b]Could not save[/b]: " + event["error"], true)
				else:
					_show_message("Game saved.")
			"loaded":
				whole = true
				_measured.clear()  # stage S14.4: a saved table's effects follow at once
				if event["error"] != "":
					_show_message("[b]Could not load[/b]: " + event["error"], true)
				else:
					failed = false
					_report_from = {}
					_loaded_at = game.steps_done()
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
					_stepped_waiting = true
			"reloaded":
				whole = true
				_measured.clear()
				if event["error"] != "":
					_show_message("[b]The model files have a problem; the game carries on with the previous model.[/b]\n%s" % event["error"], true)
				else:
					failed = false
					_model_changed()
					var reset: PackedStringArray = event["reset"]
					var note := "Model reloaded: changes take effect from next month."
					if not reset.is_empty():
						note += " These started again from their initial values: " + ", ".join(reset)
					_show_message(note)
					_stepped_waiting = true
	if _stepped_waiting and game.is_busy() and not whole:
		_show_date()  # the months still running: the date counts
		return
	if _stepped_waiting or whole:
		var stepped := _stepped_waiting
		_stepped_waiting = false
		_note_situations()
		_refresh(stepped)
		if stepped:
			_want_effects()
			# Stage S13.6: once the months asked for have all run, the report (or, after a new
			# game's opening month, the guide on a first game).
			if _opening:
				_opening = false
				_report_from = {}
				if should_guide(true, DisplayServer.get_name() == "headless", guide_seen()):
					show_guide.call_deferred()
			elif not _report_from.is_empty():
				_build_report()
	elif _status.text == "working…" and not game.is_busy():
		_set_controls(not failed and not lost)
