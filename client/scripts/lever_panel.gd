extends VBoxContainer
## Stage S13.2: a policy's popup. Its name, pictogram, area and what it is; one control per
## lever (a slider and an exact field, in the units the screen shows: rates in percent,
## large amounts in millions or billions, flows at the rate amounts are shown), the setting
## now and the change waiting (with Undo), what a change costs in political capital and the
## Commons vote it would get; what the waiting change would do in a year; and the lever's
## history with the player's changes marked.
##
## Stage S13.4: the controls come first; the year's bars are sage or brick where the scenario says
## which way is better, and the groups most affected follow the indicators. Fields read as
## people write numbers: £12,570, 21%, 21.5%, £12.38bn.
##
## Stage S13.5: a level policy is chosen by name on a row of steps; an age or a year is a
## whole number ("18 years", "2030"); a duty set as a multiple of 2024's rates reads as a
## change on today's ("as now", "+20%"), fuel duty in pence. A policy not in force opens to be
## introduced: its control starts at its `off` setting, "In a year" and the Commons vote
## follow the setting picked, and nothing is put to the Commons until "Put to the Commons".
## A policy in force that has an `off` setting can be repealed, with its cost and its vote.

const Palette := preload("res://scripts/palette.gd")
const Chart := preload("res://scripts/chart.gd")
const Bar := preload("res://scripts/bar.gd")
const Format := preload("res://scripts/format.gd")
const Sound := preload("res://scripts/sound.gd")

signal lever_changed(name: String, raw: String)
signal lever_cancelled(name: String)
## The player asked for an indicator's or a group's popup (from the year-ahead table).
signal follow(name: String)
## Stage S13.5: a setting picked for a policy being introduced (not yet a bill), and a
## repeal asked for.
signal draft_changed(name: String, raw: String)
signal repeal_pressed(name: String)
## Stage S14.1: "More" opened or closed (the popup fits itself again).
signal more_toggled

## Stage S13.6: the window width from which popups had two columns (stage S14.1: none do;
## kept for callers).
const WIDE_FROM := 1360.0

var fmt: RefCounted
var key := ""  # the board's policy key
var levers: PackedStringArray = []
## Stage S14.1: unused; a policy's popup is always one column.
var wide := false
var capital_note: Label
var chart: Chart
var _rows := {}  # name -> {entry, spin, slider, now, pending, cancel, vote}
var _units := {}  # name -> amount one unit of a money input stands for: 1, 1e6 or 1e9
var _dragging := ""
var _chart_lever := ""
## The year-ahead table as shown: [label, change] per row, for tests; groups in year_groups.
var year_shown: Array = []
var year_groups: Array = []
var year_all_groups: Array = []  # every group's change, shown or not
var year_heading := ""
## Stage S14.4: true while a forecast is being worked out (the last figures shown greyed).
var measuring := false
## Stage S13.5 (set before build): true to introduce the policy, and its `off` setting as
## the engine stores it (null for a policy that cannot be repealed).
var introducing := false
var off_stored: Variant = null
## The setting picked while introducing: lever -> [raw as typed, value as stored].
var draft := {}
## What the setting picked would cost in political capital (set by the screen).
var draft_cost := -1.0
var put_button: Button
var repeal_button: Button
var repeal_note: Label
var _controls: VBoxContainer
var _holder: VBoxContainer  # where the next lever's row goes: the main controls or "More"
var _more: VBoxContainer
var _history: VBoxContainer
var _year: VBoxContainer
var _year_title: Label
var _year_note: Label
var _year_rows: GridContainer
var _group_title: Label
var _group_rows: GridContainer


## A lever's exact field: the number as people write it, read back however it is typed
## (separators, a symbol or a unit are ignored); the up and down keys step it.
class Field extends LineEdit:
	signal value_changed(value: float)
	var value := 0.0
	var min_value := -1e15
	var max_value := 1e15
	var step := 0.01
	var arrow_step := 1.0
	var prefix := ""
	var suffix := ""
	## For money: the amount one unit of the value stands for (1, a million or a billion);
	## the field shows the amount itself, short (£125,140, £812.4m, £12.38bn).
	var money_unit := 0.0
	## Stage S13.5: "+" before a rise, words for nought ("as now"), a year without separators.
	var signed := false
	var zero_text := ""
	var plain := false

	func _ready() -> void:
		text_submitted.connect(func(_t: String) -> void: _read())
		focus_exited.connect(_read)
		_show()

	## Sets the value; `notify` sends value_changed when it changed.
	func apply(v: float, notify := true) -> void:
		v = clampf(snappedf(v, step), min_value, max_value)
		var changed := not is_equal_approx(v, value)
		value = v
		_show()
		if notify and changed:
			value_changed.emit(value)

	func _read() -> void:
		var digits := ""
		for ch in text.replace("−", "-"):
			if ch in "0123456789.-":
				digits += ch
		if not digits.is_valid_float():
			_show()
			return
		if money_unit > 0.0:
			var said := text.to_lower()
			var times := 1e9 if said.contains("b") else (1e6 if said.contains("m") else (1e3 if said.contains("k") else 1.0))
			apply(float(digits) * times / money_unit)
		else:
			apply(float(digits))

	func _show() -> void:
		if money_unit > 0.0:
			var amount := value * money_unit
			text = ("−" if amount < 0.0 else "") + prefix + Format.compact(absf(amount))
			return
		if zero_text != "" and is_zero_approx(value):
			text = zero_text
			return
		var places := 0
		for d in [0, 1, 2, 3]:
			places = d
			if is_equal_approx(snappedf(value, pow(10.0, -d)), value):
				break
		var body := "%d" % int(roundf(value)) if plain else Format.grouped(value, places)
		text = ("+" if signed and value > 0.0 else "") + prefix + body + suffix

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]:
			apply(value + (arrow_step if event.keycode == KEY_UP else -arrow_step))
			accept_event()


## Stored value to input value: rates as percentages; money in major units, or millions
## or billions for large amounts; flows at the rate the screen shows them (a year or a
## step).
func _scale(entry: Dictionary) -> float:
	if fmt.is_rate(entry) or str(entry.get("show_as", "")) == "multiple":
		return 100.0
	if entry.get("money", false):
		return fmt.factor(entry, false) / float(fmt.minor) / float(_units.get(entry["name"], 1.0))
	return fmt.factor(entry, false)


## Stage S13.5: what is taken from a stored value before scaling: a multiple of 2024's rates
## is shown as its change on them.
static func _offset(entry: Dictionary) -> float:
	return 1.0 if str(entry.get("show_as", "")) == "multiple" else 0.0


## Large amounts are typed in millions or billions, judged by the top of the range.
func _money_unit(entry: Dictionary) -> float:
	if not entry.get("has_range", false):
		return 1.0
	var top: float = absf(float(entry["max"])) * fmt.factor(entry, false) / float(fmt.minor)
	if top >= 1e10:
		return 1e9
	if top >= 1e7:
		return 1e6
	return 1.0


## The popup's width for this content. Stage S14.1: one column, never wider than 640 pixels.
func popup_width() -> float:
	return 640.0


## Stage S14.1: the levers a policy opens with: its first, and any rate among its first three
## (Income tax's three rates, not its thresholds); the rest wait under "More".
func _is_main(index: int, entry: Dictionary) -> bool:
	return index == 0 or (index < 3 and fmt.is_rate(entry))


## `node` is the board's policy node; `entries` the levers' catalogue entries in order;
## `start_of(name)` where a lever began (the slider spans up to twice that for a lever
## whose range is far wider than play). Stage S14.1: one column: the main control(s), the
## cost and the vote they would get, "More" for the other levers, then the history, which
## "In a year" replaces once a control has moved.
func build(node: Dictionary, entries: Array, legislature: bool, start_of: Callable) -> void:
	key = str(node.get("key", ""))
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var badge := TextureRect.new()
	badge.texture = Palette.sized(node.get("icon"), 56)
	badge.custom_minimum_size = Vector2(56, 56)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = Palette.INK
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(Palette.caps(str(node.get("area", "Policy")) + (" · not in force" if introducing else "")))
	var title := Label.new()
	title.text = str(node.get("long_label", node.get("label", "")))
	title.theme_type_variation = "Title"
	titles.add_child(title)
	if entries.size() == 1 and str(entries[0].get("doc", "")) != "":
		add_child(Palette.content(_muted(Palette.lead(str(entries[0]["doc"]))), str(entries[0]["doc"])))
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 8)
	add_child(_controls)
	var rest := []
	for i in entries.size():
		if _is_main(i, entries[i]):
			_holder = _controls
			_lever_row(entries[i], start_of.call(str(entries[i]["name"])))
		else:
			rest.append(entries[i])
		levers.append(str(entries[i]["name"]))
	if not rest.is_empty():
		var more := Button.new()
		more.name = "more"
		more.theme_type_variation = "Link"
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var words := "More: %s" % ", ".join(rest.map(func(e): return str(e.get("label", e["name"])).to_lower()))
		more.text = "▶  " + (words if words.length() <= 70 else "More: %d further settings" % rest.size())
		_controls.add_child(more)
		_more = VBoxContainer.new()
		_more.name = "more_controls"
		_more.add_theme_constant_override("separation", 12)
		_more.visible = false
		_controls.add_child(_more)
		var shown_words := more.text.trim_prefix("▶  ")
		more.pressed.connect(func() -> void:
			_more.visible = not _more.visible
			more.text = ("▼  " if _more.visible else "▶  ") + shown_words  # the folds' own triangles
			more_toggled.emit())
		for entry in rest:
			_holder = _more
			_lever_row(entry, start_of.call(str(entry["name"])))
	# Stage S13.5: the bill that brings the policy in, or the one that repeals it.
	if introducing and not levers.is_empty():
		put_button = Button.new()
		put_button.name = "put_to_commons"
		put_button.text = "Put to the Commons" if legislature else "Bring it in"
		put_button.theme_type_variation = "Primary"
		put_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		put_button.disabled = true
		var first := levers[0]
		put_button.pressed.connect(func() -> void:
			if draft.has(first):
				lever_changed.emit(first, str(draft[first][0])))
		_controls.add_child(put_button)
	elif off_stored != null and not levers.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		repeal_button = Button.new()
		repeal_button.name = "repeal"
		repeal_button.text = "Repeal"
		repeal_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var first := levers[0]
		repeal_button.pressed.connect(func() -> void: repeal_pressed.emit(first))
		row.add_child(repeal_button)
		repeal_note = _muted("")
		repeal_note.custom_minimum_size.x = 300
		repeal_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(repeal_note)
		_controls.add_child(row)
	capital_note = _muted("")
	capital_note.name = "capital_note"
	capital_note.visible = false
	_controls.add_child(capital_note)
	_year = VBoxContainer.new()
	_year.name = "in_a_year"
	_year.add_theme_constant_override("separation", 8)
	_year.visible = false
	add_child(_year)
	_year_title = Palette.caps("In a year")
	_year.add_child(_year_title)
	_year_note = _muted("")
	_year_note.visible = false
	_year.add_child(_year_note)
	_year_rows = _table()
	_year.add_child(_year_rows)
	_group_title = Palette.caps("The groups it moves most")
	_group_title.visible = false
	_year.add_child(_group_title)
	_group_rows = _table()
	_year.add_child(_group_rows)
	_chart_lever = levers[0] if not levers.is_empty() else ""
	# Stage S13.5: a policy not in force has no history to show, and a level policy's names
	# do not fit a chart's axis (its setting and its changes are told above).
	if introducing or (_chart_lever != "" and _rows[_chart_lever]["entry"].has("levels")):
		return
	_history = VBoxContainer.new()
	_history.add_theme_constant_override("separation", 8)
	add_child(_history)
	_history.add_child(Palette.caps("History" if levers.size() == 1 else "History: " + str(_rows[_chart_lever]["entry"].get("label", _chart_lever))))
	chart = Chart.new()
	chart.fmt = fmt
	chart.custom_minimum_size = Vector2(0, 160)
	_history.add_child(chart)


## Stage S14.1: "In a year" stands where the history was, once a control has moved.
func _show_year_part(on: bool) -> void:
	_year.visible = on
	if _history != null:
		_history.visible = not on


func _table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## A doc string as a sentence: a full stop added unless it ends in one.
static func _sentence(words: String) -> String:
	return words if words.ends_with(".") or words.ends_with("?") or words.ends_with("!") else words + "."


func _muted(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.theme_type_variation = "Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	return label


func _lever_row(entry: Dictionary, start: Variant) -> void:
	var name: String = entry["name"]
	if entry.get("money", false):
		_units[name] = _money_unit(entry)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", _thin_rule())
	box.add_child(rule)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var label := Label.new()
	label.text = str(entry["label"])
	label.tooltip_text = str(entry.get("doc", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_override("font", Palette.text(600))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	var now := Label.new()
	now.theme_type_variation = "Muted"
	top.add_child(now)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	box.add_child(controls)
	var levels: Array = entry.get("levels", [])
	if not levels.is_empty():
		# Stage S13.5: a level policy's settings, each a labelled step; the one in force (or
		# chosen) pressed.
		controls.add_theme_constant_override("separation", 8)
		var steps := []
		var lowest := float(entry.get("min", 0.0))
		for i in levels.size():
			var step := Button.new()
			step.name = "level_%s_%d" % [name, i]
			step.text = str(levels[i])
			step.theme_type_variation = "Step"
			step.toggle_mode = true
			step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			step.custom_minimum_size = Vector2(60, 44)
			var value := lowest + i
			step.pressed.connect(func() -> void:
				Sound.play("change")
				_typed(name, value))
			controls.add_child(step)
			steps.append(step)
		_finish_row(name, entry, box, null, null, steps)
		return
	var slider := HSlider.new()
	Palette.ring_when_focused(slider)  # stage S17.1
	slider.name = "slider_" + name
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 24)
	controls.add_child(slider)
	var spin := Field.new()
	spin.custom_minimum_size = Vector2(150, 0)
	spin.name = "lever_" + name
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var scale := _scale(entry)
	var offset := _offset(entry)
	var rate: bool = fmt.is_rate(entry)
	var money: bool = entry.get("money", false)
	var as_shown := str(entry.get("show_as", ""))
	if entry.get("has_range", false):
		spin.min_value = (float(entry["min"]) - offset) * scale
		spin.max_value = (float(entry["max"]) - offset) * scale
	if as_shown == "multiple":
		spin.step = 1.0
		spin.arrow_step = 5.0
		spin.suffix = "%"
		spin.signed = true
		spin.zero_text = "as now"
	elif as_shown == "pence":
		spin.step = 0.01
		spin.arrow_step = 1.0
		spin.suffix = "p"
	elif as_shown in ["years", "year"]:
		spin.step = 1.0
		spin.suffix = " years" if as_shown == "years" else ""
		spin.plain = as_shown == "year"
	elif rate:
		spin.step = 0.1
		spin.arrow_step = 0.5
		spin.suffix = "%"
	elif money:
		var unit: float = _units[name]
		spin.step = 0.001 if unit > 1.0 else 0.01
		spin.arrow_step = 1.0 if unit > 1.0 else 10.0
		spin.prefix = fmt.symbol
		spin.money_unit = unit
	else:
		spin.step = 1.0
	spin.tooltip_text = str(entry.get("doc", ""))
	spin.value_changed.connect(func(value: float) -> void: _typed(name, value))
	controls.add_child(spin)
	# The slider spans the lever's range, or nought to twice where it began when the range
	# is far wider than play (spending lines go up to ten times their start).
	slider.min_value = spin.min_value
	slider.max_value = spin.max_value
	if start != null and entry.get("has_range", false) and float(entry["min"]) == 0.0 and float(start) > 0.0 \
			and float(entry["max"]) > 4.0 * float(start):
		slider.max_value = 2.0 * float(start) * scale
	slider.step = spin.step
	slider.value_changed.connect(func(value: float) -> void:
		Sound.play("change")
		spin.apply(value, _dragging != name))
	slider.drag_started.connect(func() -> void: _dragging = name)
	slider.drag_ended.connect(func(changed: bool) -> void:
		_dragging = ""
		if changed:
			_typed(name, spin.value))
	_finish_row(name, entry, box, spin, slider, [])


## The rest of a lever's row: the change waiting (with Undo) and the vote it would get.
func _finish_row(name: String, entry: Dictionary, box: VBoxContainer, spin: Field, slider: HSlider, steps: Array) -> void:
	var now: Label = box.get_child(1).get_child(1)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var pending := Label.new()
	pending.add_theme_color_override("font_color", Palette.PENDING)
	pending.add_theme_font_override("font", Palette.text(600))
	pending.add_theme_font_size_override("font_size", Palette.SMALL)
	pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(pending)
	var cancel := Button.new()
	cancel.text = "Undo"
	cancel.theme_type_variation = "Link"
	cancel.visible = false
	cancel.pressed.connect(func() -> void: lever_cancelled.emit(name))
	bottom.add_child(cancel)
	var vote := Label.new()
	vote.theme_type_variation = "Muted"
	vote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vote.visible = false
	box.add_child(vote)
	_holder.add_child(box)
	_rows[name] = {"entry": entry, "spin": spin, "slider": slider, "steps": steps, "now": now, "pending": pending, "cancel": cancel, "vote": vote}


static func _thin_rule() -> StyleBoxLine:
	var rule := StyleBoxLine.new()
	rule.color = Palette.RULE
	rule.thickness = 1
	return rule


func _typed(name: String, value: float) -> void:
	var entry: Dictionary = _rows[name]["entry"]
	var raw := ""
	var per_step: float = fmt.factor(entry, false)
	if entry.has("levels") or (str(entry.get("type", "")) == "int" and not entry.get("money", false)):
		raw = "%d" % int(roundf(value / per_step))
	elif _offset(entry) != 0.0:
		raw = String.num(value / 100.0 + _offset(entry), 6)
	elif fmt.is_rate(entry):
		raw = String.num(value / 100.0, 6)
	elif entry.get("money", false):
		raw = String.num(value * float(_units[name]) / per_step, 2)
	else:
		raw = String.num(value / per_step, 6)
	if introducing:
		# Stage S13.5: only a draft until it is put to the Commons.
		var stored: float = float(raw) * (fmt.minor if entry.get("money", false) else 1)
		if off_stored != null and absf(stored - float(off_stored)) < 1e-6:
			draft.erase(name)
		else:
			draft[name] = [raw, stored]
		if put_button != null:
			put_button.disabled = draft.is_empty()
		draft_changed.emit(name, raw)
		return
	lever_changed.emit(name, raw)


## Stage S15.1: a policy being introduced, set to `raw` (as a bill takes it) as if picked.
func preset(name: String, raw: String) -> void:
	if not introducing or not _rows.has(name):
		return
	var entry: Dictionary = _rows[name]["entry"]
	draft[name] = [raw, float(raw) * (fmt.minor if entry.get("money", false) else 1)]
	if put_button != null:
		put_button.disabled = false
	draft_changed.emit(name, raw)


## Shows current settings and changes waiting for next month.
## `costs`: each waiting change's cost in political capital (stage S12.5); `capital`: what
## there is to spend, or -1 for a model without it.
func refresh(current: Callable, pending: Dictionary, costs := {}, capital := -1.0) -> void:
	var waiting_total := 0.0
	for c in costs.values():
		waiting_total += maxf(float(c), 0.0)
	for name in _rows:
		var row: Dictionary = _rows[name]
		var entry: Dictionary = row["entry"]
		var value: Variant = current.call(name)
		var said: String = fmt.value(entry, value, false, false) if value != null else ""
		row["now"].text = "" if value == null else ("not in force" if introducing else (said if said.to_lower().contains("as now") else "now " + said))
		var shown: Variant = pending.get(name, value)
		if introducing:
			shown = draft[name][1] if draft.has(name) else off_stored
		var spin: Field = row["spin"]
		var at: float = (float(shown) - _offset(entry)) * _scale(entry) if shown != null else 0.0
		if spin != null and shown != null and not spin.has_focus():
			spin.apply(at, false)
		if spin != null and shown != null and _dragging != name:
			row["slider"].set_value_no_signal(at)
		var steps: Array = row["steps"]
		for i in steps.size():
			var chosen: bool = shown != null and int(roundf(float(shown) - float(entry.get("min", 0.0)))) == i
			var step: Button = steps[i]
			step.set_pressed_no_signal(chosen)
			# A step chosen but not yet in force is ochre, the colour of what waits.
			var waits: bool = chosen and (introducing or pending.has(name))
			if waits:
				step.add_theme_stylebox_override("pressed", Palette._flat(Palette.OCHRE, Palette.INK, 2, 4, 8, 0))
				step.add_theme_color_override("font_pressed_color", Palette.INK)
			else:
				step.remove_theme_stylebox_override("pressed")
				step.remove_theme_color_override("font_pressed_color")
		var repeal: bool = off_stored != null and pending.has(name) and absf(float(pending[name]) - float(off_stored)) < 1e-6
		if repeal_button != null:
			repeal_button.get_parent().visible = not repeal
		if introducing:
			row["pending"].text = "" if not draft.has(name) else "→ %s if the bill passes%s" % [fmt.value(entry, draft[name][1], false, false),
				"" if draft_cost < 0.0 else " · costs %.1f political capital%s" % [draft_cost, _left_words(capital, waiting_total + draft_cost)]]
			row["cancel"].visible = false
		elif pending.has(name):
			var cost: float = costs.get(name, -1.0)
			row["pending"].text = "→ %s from next month%s" % ["repealed" if repeal else fmt.value(entry, pending[name], false, false),
				"" if cost < 0.0 else " · costs %.1f political capital%s" % [cost, _left_words(capital, waiting_total)]]
			row["cancel"].visible = true
		else:
			row["pending"].text = ""
			row["cancel"].visible = false
			row["vote"].visible = false
		# Stage S14.1: no empty line under a control with nothing waiting.
		row["pending"].get_parent().visible = row["pending"].text != ""
	# Stage S16.1: the capital there is, and what the bills waiting (and this one) would leave.
	capital_note.visible = capital >= 0.0
	if capital >= 0.0:
		var spend := waiting_total + (maxf(draft_cost, 0.0) if introducing and not draft.is_empty() else 0.0)
		var short := spend > capital + 1e-9
		# Stage S19: said only when bills are waiting (the top bar has the capital itself).
		var whose := "With this bill, the bills waiting cost" if introducing else "The bills waiting cost"
		capital_note.visible = short  # each bill's own line says its cost and what is left
		capital_note.text = ("%s %.1f, %.1f more than there is: the bills that come last are refused." % [whose, spend, spend - capital]) if short \
			else "%s %.1f of %.1f political capital." % [whose, spend, capital]
		capital_note.add_theme_color_override("font_color", Palette.BAD if short else Palette.MUTED)


## ", 54.1 of 67.7 left": what the capital would be after `spend`; "" without capital.
static func _left_words(capital: float, spend: float) -> String:
	if capital < 0.0:
		return ""
	if spend > capital + 1e-9:
		return ", %.1f more than the %.1f there is" % [spend - capital, capital]
	return ", %.1f of %.1f left" % [capital - spend, capital]


## The Commons vote a waiting change would get (the bridge's vote_preview), and whether the
## political capital left (`left`, after the other bills waiting) pays for it.
func show_vote(name: String, preview: Dictionary, left := -1.0) -> void:
	if not _rows.has(name) or preview.is_empty():
		return
	var vote: Label = _rows[name]["vote"]
	if not preview.get("bill", true):
		vote.visible = false
		return
	var votes := int(preview.get("votes_for", 0))
	var against := int(preview.get("seats", 0)) - votes
	var passes: bool = preview.get("passes", false)
	var text := ("The Commons would pass this %d to %d." if passes else "The Commons would vote this down, %d to %d.") % [votes, against]
	var affordable: bool = preview.get("affordable", true)
	var cost := float(preview.get("cost", -1.0))
	if not affordable and cost >= 0.0:
		text += " Not enough political capital: needs %.1f, %.1f left." % [cost, maxf(left, 0.0)]
	vote.text = text
	vote.add_theme_color_override("font_color", Palette.GOOD if passes and affordable else Palette.BAD)
	vote.visible = true


## Stage S13.5: what repealing the policy would cost in political capital and the vote it
## would get (the bridge's vote_preview), with `left` the capital the other bills leave.
func show_repeal(cost: float, preview: Dictionary, left := -1.0) -> void:
	if repeal_note == null:
		return
	var words := PackedStringArray()
	if cost >= 0.0:
		words.append("Costs %.1f political capital." % cost)
	if preview.get("bill", false):
		var votes := int(preview.get("votes_for", 0))
		var against := int(preview.get("seats", 0)) - votes
		words.append(("The Commons would pass it %d to %d." if preview.get("passes", false) else "The Commons would vote it down, %d to %d.") % [votes, against])
	var short := cost >= 0.0 and left >= 0.0 and cost > left
	if short:
		words.append("Only %.1f left." % maxf(left, 0.0))
	repeal_note.text = " ".join(words)
	# Stage S17.1: a repeal that cannot be paid for says so in the colour of a refusal.
	repeal_note.add_theme_color_override("font_color", Palette.BAD if short else Palette.MUTED)


## What the changes waiting would do in a year, as signed bars: `rows` is the forecast's
## {row: [as is, without the change]}, `shown` the [row key, label, entry, kind, tier,
## better] that may be listed: the first always, then the three budget lines (kind
## "budget") and the six other rows that move most; and, under them, the five groups
## (kind "group") whose approval moves most.
func show_year(rows: Dictionary, shown: Array, working := false, heading := "") -> void:
	_show_year_part(true)
	if working:
		# Stage S14.4: the last figures stay, greyed, under a small "measuring" mark, until the
		# new ones replace them; nothing jumps or goes blank while the engine works.
		measuring = true
		var any := _year_rows.get_child_count() > 0
		_year_title.text = (year_heading if any and year_heading != "" else "IN A YEAR") + "  ·  MEASURING…"
		_year_note.visible = false  # stage S19: the heading says it is being measured
		for grid in [_year_rows, _group_rows, _group_title]:
			grid.modulate.a = 0.4
		return
	measuring = false
	for grid in [_year_rows, _group_rows, _group_title]:
		grid.modulate.a = 1.0
	_year_note.visible = false
	for grid in [_year_rows, _group_rows]:
		for child in grid.get_children():
			grid.remove_child(child)  # at once, so the popup fits itself to what is left
			child.queue_free()
	_group_title.visible = false
	# Stage S13.5: the heading says the setting in the policy's own words ("at £2,500 a car").
	_year_title.text = ("IN A YEAR, " + heading if heading != "" else "IN A YEAR, WITH THE CHANGE").to_upper()
	year_heading = _year_title.text
	var items := []
	for item in shown:
		var row := str(item[0]).trim_prefix("-")
		if not rows.has(row):
			continue
		var pair: Array = rows[row]
		var d := float(pair[0]) - float(pair[1])
		if str(item[0]).begins_with("-"):
			d = -d
		var base := maxf(absf(float(pair[1])), 1e-9)
		# How far it moves for its size (a rate against at least two points), weighted by how
		# much the row matters (its tier on the board, squared; budget lines count as 2).
		var size := absf(d) / maxf(absf(float(pair[1])), 0.02) if fmt.is_rate(item[2]) else absf(d) / base
		var weight := pow(float(item[4]) if item.size() > 4 else 2.0, 2.0)
		items.append([item, d, size * weight, size])
	if items.is_empty():
		_show_year_part(false)
		return
	var kind := func(it: Array) -> String: return str(it[0][3]) if it[0].size() > 3 else ""
	# The first row (the budget balance) stays first; the rest, the largest moves.
	var first: Array = items.slice(0, 1)
	var rest: Array = items.slice(1).filter(func(it): return it[2] > 1e-5)
	rest.sort_custom(func(a, b): return a[2] > b[2])
	var board_rows: Array = rest.filter(func(it): return not kind.call(it) in ["budget", "group"])
	var budget_rows: Array = rest.filter(func(it): return kind.call(it) == "budget")
	var group_items: Array = rest.filter(func(it): return kind.call(it) == "group")
	group_items.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	group_items = group_items.slice(0, 5)
	items = first + budget_rows.slice(0, 3) + board_rows.slice(0, 6)
	year_shown = items.map(func(it): return [str(it[0][1]), float(it[1])])
	year_groups = group_items.map(func(it): return [str(it[0][1]), float(it[1])])
	year_all_groups = rest.filter(func(it): return kind.call(it) == "group").map(func(it): return [str(it[0][1]), float(it[1])])
	_fill(_year_rows, items, false)
	_group_title.visible = not group_items.is_empty()
	_fill(_group_rows, group_items, true)


## Bars for some rows of the year ahead, longest for the largest move; groups by their
## change in points of approval.
func _fill(grid: GridContainer, items: Array, groups: bool) -> void:
	var biggest := 1e-12
	for it in items:
		biggest = maxf(biggest, absf(it[1]) if groups else it[3])
	for it in items:
		var item: Array = it[0]
		var name := Button.new()
		name.text = str(item[1])
		name.theme_type_variation = "LinkRow"
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Stage S17.1: one width for the names in both tables (what it would do, who would
		# cheer), so their bars start from one line; a longer name is cut short, whole in its tooltip.
		name.custom_minimum_size = Vector2(230, 0)
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.tooltip_text = str(item[1])
		var target := str(item[6]) if item.size() > 6 else str(item[2].get("name", ""))
		name.pressed.connect(func() -> void: follow.emit(target))
		grid.add_child(name)
		var said: String = fmt.change(item[2], it[1])
		var bar := Bar.new()
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Stage S17.1: no bar beside "no change" (a move too small to show had a sliver of one).
		bar.fraction = 0.0 if said == fmt.change(item[2], 0.0) else ((absf(it[1]) if groups else it[3]) / biggest) * signf(it[1])
		# Sage for a change for the better, brick for the worse, where that is known.
		var better := str(item[5]) if item.size() > 5 else ""
		bar.up_colour = Palette.INK if better == "" else (Palette.SAGE if better == "high" else Palette.BRICK)
		bar.down_colour = Palette.INK if better == "" else (Palette.BRICK if better == "high" else Palette.SAGE)
		grid.add_child(bar)
		var amount := Label.new()
		amount.text = said
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.custom_minimum_size = Vector2(110, 0)
		grid.add_child(amount)


func hide_year() -> void:
	_show_year_part(false)
	for grid in [_year_rows, _group_rows]:
		for child in grid.get_children():
			grid.remove_child(child)  # at once, so the popup fits itself to what is left
			child.queue_free()
	_group_title.visible = false
	_year_title.text = "IN A YEAR"


## The first lever's history, with the player's past changes to any of the policy's levers.
func show_history(steps: PackedInt64Array, values: PackedFloat64Array, markers: Array) -> void:
	if _chart_lever == "" or chart == null:
		return
	var entry: Dictionary = _rows[_chart_lever]["entry"]
	var k: float = fmt.factor(entry)
	for i in values.size():
		values[i] *= k
	chart.entry = entry
	chart.series = [{"row": _chart_lever, "label": str(entry.get("label", _chart_lever)), "values": values, "color": Palette.BLUE}]
	chart.set_data(steps, markers)


func chart_lever() -> String:
	return _chart_lever


## For tests: types a value into a lever's input as a player would. The value is in the
## lever's own terms: money in major units a step, rates in percent.
func type_value(name: String, value: float) -> void:
	var entry: Dictionary = _rows[name]["entry"]
	var spin: Field = _rows[name]["spin"]
	if spin == null:
		_typed(name, value)  # a level, by its value
	elif _offset(entry) != 0.0:
		spin.apply((value - _offset(entry)) * _scale(entry))
	elif fmt.is_rate(entry):
		spin.apply(value)
	elif entry.get("money", false):
		spin.apply(value * float(fmt.minor) * _scale(entry))
	else:
		spin.apply(value * _scale(entry))


## For tests: what a lever's field reads.
func field_text(name: String) -> String:
	if not _rows.has(name):
		return ""
	if _rows[name]["spin"] == null:
		for step in _rows[name]["steps"]:
			if step.button_pressed:
				return step.text
		return ""
	return str(_rows[name]["spin"].text)


## Stage S13.5: the names on a level policy's steps, in order.
func level_names(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for step in _rows.get(name, {}).get("steps", []):
		out.append(step.text)
	return out


func pending_text(name: String) -> String:
	return str(_rows[name]["pending"].text) if _rows.has(name) else ""
