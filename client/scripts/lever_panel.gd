extends PanelContainer
## The player's policy levers, generated from the model: one row per lever with its
## current setting, an input, and the change waiting for next month.

const Palette := preload("res://scripts/palette.gd")

signal lever_changed(name: String, raw: String)
signal lever_cancelled(name: String)
signal explain_requested(name: String)

var hint: Label
var fmt: RefCounted
var _rows := {}  # name -> {entry, spin, now, pending, cancel}
var _units := {}  # name -> amount one unit of a money input stands for: 1, 1e6 or 1e9
var _groups := {}  # group -> {button, rows, open}
## Groups shown open at the start; the rest start folded (a model can have dozens of levers).
const OPEN_GROUPS := ["", "Spending", "Taxes", "Income tax"]
var _list: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Policy"
	title.theme_type_variation = "Title"
	box.add_child(title)
	hint = Label.new()
	hint.text = "Changes take effect from next month."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Palette.MUTED)
	hint.add_theme_font_size_override("font_size", Palette.SMALL)
	box.add_child(hint)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)


## Stored value to input value: rates as percentages; money in major units, or millions
## or billions for large amounts; flows at the rate the screen shows them (a year or a
## step).
func _scale(entry: Dictionary) -> float:
	if fmt.is_rate(entry):
		return 100.0
	if entry.get("money", false):
		return fmt.factor(entry, false) / float(fmt.minor) / float(_units.get(entry["name"], 1.0))
	return fmt.factor(entry, false)


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


## With a legislature (stage S5.4) a change to a lever with a leaning is a bill.
func set_legislature(on: bool) -> void:
	hint.text = ("Changes are bills: the House of Commons votes on them at the start of next month, and a "
		+ "government without a majority of its own can lose them.") if on else "Changes take effect from next month."


func build(levers: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	_units.clear()
	_groups.clear()
	for entry in levers:
		var name: String = entry["name"]
		var group := str(entry.get("group", ""))
		if group != "" and not _groups.has(group):
			var header := Button.new()
			header.flat = true
			header.alignment = HORIZONTAL_ALIGNMENT_LEFT
			header.name = "group_" + group.replace(" ", "_")
			header.theme_type_variation = "Link"
			header.add_theme_font_size_override("font_size", Palette.FONT_SIZE + 1)
			_list.add_child(header)
			_groups[group] = {"button": header, "rows": [], "open": OPEN_GROUPS.has(group)}
			header.pressed.connect(func() -> void: _toggle(group))
		if entry.get("money", false):
			_units[name] = _money_unit(entry)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = entry["label"]
		label.tooltip_text = entry["doc"]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(label)
		var now := Label.new()
		now.add_theme_color_override("font_color", Palette.MUTED)
		top.add_child(now)
		var spin := SpinBox.new()
		spin.custom_minimum_size = Vector2(170, 0)
		spin.name = "lever_" + name
		var scale := _scale(entry)
		var rate: bool = fmt.is_rate(entry)
		var money: bool = entry.get("money", false)
		if entry.get("has_range", false):
			spin.min_value = float(entry["min"]) * scale
			spin.max_value = float(entry["max"]) * scale
		else:
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.max_value = 1e15
			spin.min_value = -1e15
		if rate:
			spin.step = 0.1
			spin.custom_arrow_step = 0.5
			spin.suffix = "%"
		elif money:
			var unit: float = _units[name]
			spin.step = 0.001 if unit > 1.0 else 0.01
			spin.custom_arrow_step = 1.0 if unit > 1.0 else 10.0
			spin.prefix = fmt.symbol
			spin.suffix = "bn" if unit == 1e9 else ("m" if unit == 1e6 else "")
		else:
			spin.step = 1.0
		spin.tooltip_text = entry["doc"]
		spin.value_changed.connect(func(value: float) -> void: _typed(name, value))
		top.add_child(spin)
		var why := Button.new()
		why.text = "Why"
		why.theme_type_variation = "Link"
		why.tooltip_text = "Show what this lever affects next to the figures it feeds."
		why.visible = false
		top.add_child(why)
		row.add_child(top)
		var bottom := HBoxContainer.new()
		var pending := Label.new()
		pending.add_theme_color_override("font_color", Palette.PENDING)
		pending.add_theme_font_size_override("font_size", Palette.SMALL)
		pending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(pending)
		var cancel := Button.new()
		cancel.text = "Undo"
		cancel.theme_type_variation = "Link"
		cancel.visible = false
		cancel.pressed.connect(func() -> void: lever_cancelled.emit(name))
		bottom.add_child(cancel)
		row.add_child(bottom)
		var line := HSeparator.new()
		line.add_theme_color_override("separator", Palette.LINE)
		row.add_child(line)
		_list.add_child(row)
		_rows[name] = {"entry": entry, "spin": spin, "now": now, "pending": pending, "cancel": cancel}
		if _groups.has(group):
			_groups[group]["rows"].append(row)
	for group in _groups:
		_show_group(group)


func _toggle(group: String) -> void:
	_groups[group]["open"] = not _groups[group]["open"]
	_show_group(group)


func _show_group(group: String) -> void:
	var g: Dictionary = _groups[group]
	var rows: Array = g["rows"]
	g["button"].text = ("▾ " if g["open"] else "▸ ") + group + ("" if g["open"] else "  (%d)" % rows.size())
	for row in rows:
		row.visible = g["open"]


func _typed(name: String, value: float) -> void:
	var entry: Dictionary = _rows[name]["entry"]
	var raw := ""
	var per_step: float = fmt.factor(entry, false)
	if fmt.is_rate(entry):
		raw = String.num(value / 100.0, 6)
	elif entry.get("money", false):
		raw = String.num(value * float(_units[name]) / per_step, 2)
	else:
		raw = String.num(value / per_step, 6)
	lever_changed.emit(name, raw)


## Shows current settings and changes waiting for next month.
func refresh(current: Callable, pending: Dictionary) -> void:
	for name in _rows:
		var row: Dictionary = _rows[name]
		var entry: Dictionary = row["entry"]
		var value: Variant = current.call(name)
		row["now"].text = fmt.value(entry, value, false, false) if value != null else ""
		var spin: SpinBox = row["spin"]
		var shown: Variant = pending.get(name, value)
		if shown != null and not spin.get_line_edit().has_focus():
			spin.set_value_no_signal(float(shown) * _scale(entry))
		if pending.has(name):
			row["pending"].text = "→ %s from next month" % fmt.value(entry, pending[name], false, false)
			row["cancel"].visible = true
		else:
			row["pending"].text = ""
			row["cancel"].visible = false


## For tests: types a value into a lever's input as a player would. The value is in the
## lever's own terms: money in major units a step, rates in percent.
func type_value(name: String, value: float) -> void:
	var entry: Dictionary = _rows[name]["entry"]
	var spin: SpinBox = _rows[name]["spin"]
	if fmt.is_rate(entry):
		spin.value = value
	elif entry.get("money", false):
		spin.value = value * float(fmt.minor) * _scale(entry)
	else:
		spin.value = value * _scale(entry)
