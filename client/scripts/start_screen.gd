extends PanelContainer
## Stage S7.1: the start screen. The player picks a scenario (every scenario file with a
## `[play] title` under the game's models folder) and any mods for its model (folders with
## a mod.toml, in the game's mods folder and the player's own), then starts a new game or
## continues the saved one. Shown when the client starts without `--scenario`.

const Palette := preload("res://scripts/palette.gd")

## A new game (`resume` false) or the saved one (`resume` true).
signal chosen(scenario_path: String, mods: PackedStringArray, resume: bool)

var scenarios: Array = []  # dictionaries from the bridge's scenarios()
var mods: Array = []  # dictionaries from the bridge's mods()
var saves_folder := ""
var user_mods := ""
var _choice: OptionButton
var _summary: Label
var _mod_box: VBoxContainer
var _ticks := {}  # mod path -> CheckBox
var _new: Button
var _continue: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", Palette.panel_style(Palette.BG, 0, 0))
	var center := CenterContainer.new()
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.panel_style())
	card.custom_minimum_size = Vector2(680, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title := Label.new()
	title.text = "PoliSim"
	title.add_theme_font_size_override("font_size", Palette.TITLE + 8)
	box.add_child(title)
	box.add_child(_muted("You lead a government. Choose a country, and any mods to play it with."))
	box.add_child(_muted("Country", true))
	_choice = OptionButton.new()
	_choice.name = "scenario_choice"
	_choice.item_selected.connect(func(_i: int) -> void: _show_choice())
	box.add_child(_choice)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	box.add_child(_muted("Mods", true))
	_mod_box = VBoxContainer.new()
	_mod_box.add_theme_constant_override("separation", 4)
	box.add_child(_mod_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_new = Button.new()
	_new.name = "new_game"
	_new.text = "New game"
	_new.pressed.connect(func() -> void: chosen.emit(selected_path(), selected_mods(), false))
	buttons.add_child(_new)
	_continue = Button.new()
	_continue.name = "continue_game"
	_continue.text = "Continue saved game"
	_continue.pressed.connect(func() -> void: chosen.emit(selected_path(), PackedStringArray(), true))
	buttons.add_child(_continue)


func _muted(text: String, small := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Palette.MUTED)
	if small:
		label.add_theme_font_size_override("font_size", Palette.SMALL)
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
