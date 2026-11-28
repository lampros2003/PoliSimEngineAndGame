extends PanelContainer
## Stage S7.1: the start screen. The player picks a scenario (every scenario file with a
## `[play] title` under the game's models folder) and any mods for its model (folders with
## a mod.toml, in the game's mods folder and the player's own), then starts a new game or
## continues the saved one. Shown when the client starts without `--scenario`. Stage S13.2: a
## card of the board's stock on the paper, with a row of the areas' pictograms over the title.

const Palette := preload("res://scripts/palette.gd")
const Plate := preload("res://scripts/plate.gd")
## Stage S18.3: the pictograms either side of the plate's roundel: the areas of government.
const ICONS := ["economy", "tax", "welfare", "health", "education", "law", "transport", "environment", "housing", "trade"]

## A new game (`resume` false) or the saved one (`resume` true), with the game's words in
## `language` ("" for the model's own; stage S7.4).
signal chosen(scenario_path: String, mods: PackedStringArray, resume: bool, language: String)

var scenarios: Array = []  # dictionaries from the bridge's scenarios()
var mods: Array = []  # dictionaries from the bridge's mods()
var saves_folder := ""
var user_mods := ""
var _choice: OptionButton
var _summary: Label
var _language_title: Label
var _language: OptionButton
var _language_codes: PackedStringArray = []
var _mod_box: VBoxContainer
var _ticks := {}  # mod path -> CheckBox
var _new: Button
var _continue: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(Palette.paper())
	var center := CenterContainer.new()
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.card(32, 10, 2))
	card.custom_minimum_size = Vector2(700, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	# Stage S18.3: a plate at the head: the seat of government in the roundel, the areas of
	# government either side of it, as on a public-information poster.
	var plate := Plate.from({"icon": "parliament", "tone": "blue", "beside": ICONS}, "parliament", "blue")
	plate.custom_minimum_size = Vector2(0, 148)
	box.add_child(plate)
	var title := Label.new()
	title.text = "PoliSim"
	title.add_theme_font_override("font", Palette.display(500))
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	var rules := Control.new()
	rules.custom_minimum_size = Vector2(0, 8)
	rules.draw.connect(func() -> void:
		rules.draw_line(Vector2(0, 1), Vector2(rules.size.x, 1), Palette.INK, 3.0)
		rules.draw_line(Vector2(0, 7), Vector2(rules.size.x, 7), Palette.INK, 1.0))
	box.add_child(rules)
	var lead := Label.new()
	lead.text = "You lead a government. Choose a country, and any mods to play it with."
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.add_theme_font_size_override("font_size", 18)
	box.add_child(lead)
	box.add_child(_muted("Country", true, true))
	_choice = OptionButton.new()
	_choice.name = "scenario_choice"
	_choice.item_selected.connect(func(_i: int) -> void: _show_choice())
	box.add_child(_choice)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	_language_title = _muted("Language", true, true)
	box.add_child(_language_title)
	_language = OptionButton.new()
	_language.name = "language_choice"
	box.add_child(_language)
	box.add_child(_muted("Mods", true, true))
	_mod_box = VBoxContainer.new()
	_mod_box.add_theme_constant_override("separation", 4)
	box.add_child(_mod_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_new = Button.new()
	_new.name = "new_game"
	_new.text = "New game"
	_new.theme_type_variation = "Primary"
	_new.pressed.connect(func() -> void: chosen.emit(selected_path(), selected_mods(), false, selected_language()))
	buttons.add_child(_new)
	_continue = Button.new()
	_continue.name = "continue_game"
	_continue.text = "Continue saved game"
	_continue.pressed.connect(func() -> void: chosen.emit(selected_path(), PackedStringArray(), true, selected_language()))
	buttons.add_child(_continue)


func _muted(text: String, small := false, heading := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Palette.MUTED)
	if small:
		label.add_theme_font_size_override("font_size", Palette.SMALL)
	if heading:
		label.text = text.to_upper()
		label.theme_type_variation = "Heading"
	return label


## Fills the screen: `found_scenarios` and `found_mods` from the bridge.
func fill(found_scenarios: Array, found_mods: Array) -> void:
	scenarios = found_scenarios
	mods = found_mods
	_choice.clear()
	for scenario in scenarios:
		_choice.add_item(str(scenario["title"]))
	if not scenarios.is_empty():
		_choice.select(0)
	_new.disabled = scenarios.is_empty()
	_show_choice()


func selected_path() -> String:
	var i := _choice.selected
	return str(scenarios[i]["path"]) if i >= 0 and i < scenarios.size() else ""


## The chosen language's code, or "" for the model's own words.
func selected_language() -> String:
	var i := _language.selected
	return _language_codes[i] if i >= 0 and i < _language_codes.size() else ""


## Picks a language by code, as a test or a player would.
func choose_language(code: String) -> bool:
	var i := _language_codes.find(code)
	if i < 0:
		return false
	_language.select(i)
	return true


func selected_mods() -> PackedStringArray:
	var out := PackedStringArray()
	for path in _ticks:
		if (_ticks[path] as CheckBox).button_pressed:
			out.append(path)
	return out


## Ticks a mod by id, as a test or a player would.
func tick(id: String, on := true) -> bool:
	for mod in mods:
		if str(mod["id"]) == id and _ticks.has(str(mod["path"])):
			(_ticks[str(mod["path"])] as CheckBox).button_pressed = on
			return true
	return false


func save_of(path: String) -> String:
	return saves_folder.path_join(path.get_file().get_basename() + ".psave")


func _show_choice() -> void:
	for child in _mod_box.get_children():
		_mod_box.remove_child(child)
		child.queue_free()
	_ticks.clear()
	var i := _choice.selected
	if i < 0 or i >= scenarios.size():
		_summary.text = "No scenarios found."
		_continue.disabled = true
		return
	var scenario: Dictionary = scenarios[i]
	_summary.text = str(scenario.get("summary", ""))
	# Stage S7.4: the model's own words first, then the languages it has text in.
	_language.clear()
	_language_codes = PackedStringArray([""])
	_language.add_item("English (the model's own words)")
	for language in scenario.get("languages", []):
		_language_codes.append(str(language["code"]))
		_language.add_item(str(language["name"]))
	_language.select(0)
	_language_title.visible = _language_codes.size() > 1
	_language.visible = _language_codes.size() > 1
	_continue.disabled = not FileAccess.file_exists(save_of(str(scenario["path"])))
	var model := str(scenario["model"])
	for mod in mods:
		if str(mod.get("model", "")) not in ["", model]:
			continue
		if str(mod.get("error", "")) != "":
			var broken := _muted("%s cannot be used: %s" % [mod["name"], mod["error"]], true)
			broken.add_theme_color_override("font_color", Palette.BAD)
			_mod_box.add_child(broken)
			continue
		var tick_box := CheckBox.new()
		var version := str(mod.get("version", ""))
		tick_box.text = str(mod["name"]) + ((" " + version) if version != "" else "")
		tick_box.tooltip_text = str(mod.get("description", ""))
		_mod_box.add_child(tick_box)
		_ticks[str(mod["path"])] = tick_box
		if str(mod.get("description", "")) != "":
			var about := _muted(str(mod["description"]), true)
			about.custom_minimum_size = Vector2(620, 0)
			_mod_box.add_child(about)
	if _ticks.is_empty():
		_mod_box.add_child(_muted("No mods for this country yet. A mod is a folder with a mod.toml: put it in %s." % user_mods, true))
