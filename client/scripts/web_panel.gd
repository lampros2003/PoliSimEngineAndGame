extends PanelContainer
## The icon web (stage S6.1): a value with what it depends on (left) and what depends on it
## (right), each as a tile showing its value and last month's change, green for a rise and
## red for a fall. Clicking a tile moves the web to it. The connections are the model's
## own: the names each formula reads, from the catalogue.

const Palette := preload("res://scripts/palette.gd")
const MOST := 10  # tiles a side; the rest are counted

signal moved(name: String)

var fmt: RefCounted
var entries := {}  # name -> catalogue entry
var consumers := {}  # name -> names of the values that read it
var center := ""
var trail: PackedStringArray = []
var _title: Label
var _back: Button
var _inputs: VBoxContainer
var _middle: VBoxContainer
var _outputs: VBoxContainer
var _latest: Callable
var _previous: Callable


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.text = "Connections"
	_title.theme_type_variation = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_back = Button.new()
	_back.text = "Back"
	_back.theme_type_variation = "Link"
	_back.disabled = true
	_back.pressed.connect(_go_back)
	head.add_child(_back)
	var hint := Label.new()
	hint.text = "What a value depends on, and what depends on it. Press a tile to move to it."
	hint.add_theme_color_override("font_color", Palette.MUTED)
	hint.add_theme_font_size_override("font_size", Palette.SMALL)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inputs = _column(row, "Depends on", scroll)
	_middle = _column(row, "", null)
	_middle.custom_minimum_size = Vector2(170, 0)
	var scroll2 := ScrollContainer.new()
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_outputs = _column(row, "Feeds", scroll2)


func _column(parent: Control, heading: String, scroll: ScrollContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading != "":
		var label := Label.new()
		label.text = heading
		label.add_theme_color_override("font_color", Palette.MUTED)
		label.add_theme_font_size_override("font_size", Palette.SMALL)
		column.add_child(label)
	if scroll != null:
		scroll.add_child(column)
		parent.add_child(scroll)
	else:
		parent.add_child(column)
	return column


## The catalogue's entries, with each value's inputs: builds who reads whom.
func build(catalogue_entries: Dictionary) -> void:
	entries = catalogue_entries
	consumers.clear()
	for name in entries:
		var entry: Dictionary = entries[name]
		for list in [entry.get("inputs", PackedStringArray()), entry.get("lagged_inputs", PackedStringArray())]:
			for used in list:
				if not consumers.has(used):
					consumers[used] = PackedStringArray()
				if not (consumers[used] as PackedStringArray).has(name):
					consumers[used].append(name)
	if center != "" and not entries.has(center):
		center = ""
		trail.clear()


func inputs_of(name: String) -> PackedStringArray:
	var entry: Dictionary = entries.get(name, {})
	var out := PackedStringArray()
	for list in [entry.get("inputs", PackedStringArray()), entry.get("lagged_inputs", PackedStringArray())]:
		for used in list:
			# Data columns and parameters never change during a run: the web leaves them out.
			if entries.has(used) and not out.has(used) and not str(entries[used].get("kind", "")) in ["column", "param"]:
				out.append(used)
	return out


func consumers_of(name: String) -> PackedStringArray:
	return consumers.get(name, PackedStringArray())


## Moves the web to a value; `push` keeps the way back.
func show_value(name: String, push := true) -> void:
	if not entries.has(name):
		return
	if push and (trail.is_empty() or trail[trail.size() - 1] != name):
		trail.append(name)
	center = name
	_back.disabled = trail.size() < 2
	moved.emit(name)
	refresh(_latest, _previous)


func _go_back() -> void:
	if trail.size() > 1:
		trail.remove_at(trail.size() - 1)
		show_value(trail[trail.size() - 1], false)


func refresh(latest: Callable, previous: Callable) -> void:
	_latest = latest
	_previous = previous
	for column in [_inputs, _middle, _outputs]:
		for child in column.get_children().slice(0 if column == _middle else 1):
			column.remove_child(child)
			child.queue_free()
	if center == "" or not latest.is_valid():
		var empty := Label.new()
		empty.text = "Press Why next to any figure, or a tile here."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_middle.add_child(empty)
		return
	_middle.add_child(_tile(center, true))
	for pair in [[_inputs, inputs_of(center)], [_outputs, consumers_of(center)]]:
		var column: VBoxContainer = pair[0]
		var names: PackedStringArray = pair[1]
		var ranked := Array(names)
		ranked.sort_custom(func(a, b): return _movement(a) > _movement(b))
		for name in ranked.slice(0, MOST):
			column.add_child(_tile(name, false))
		if ranked.size() > MOST:
			var more := Label.new()
			more.text = "and %d more" % (ranked.size() - MOST)
			more.add_theme_color_override("font_color", Palette.MUTED)
			column.add_child(more)
		if ranked.is_empty():
			var none := Label.new()
			none.text = "nothing" if column == _outputs else "no inputs: set by the player or fixed"
			none.add_theme_color_override("font_color", Palette.MUTED)
			none.add_theme_font_size_override("font_size", Palette.SMALL)
			column.add_child(none)


## The value of an entry and of last month: national values and totals only.
func _values(name: String) -> Array:
	var entry: Dictionary = entries.get(name, {})
	var row := str(entry.get("row", ""))
	if row == "" or not _latest.is_valid():
		return [null, null]
	return [_latest.call(row), _previous.call(row)]


## How much a value moved last month, as a share of its size: the tiles that moved most
## come first.
func _movement(name: String) -> float:
	var v := _values(name)
	if v[0] == null or v[1] == null or typeof(v[0]) == TYPE_BOOL:
		return 0.0
	var now := float(v[0])
	var before := float(v[1])
	return absf(now - before) / maxf(absf(before), 1e-12)


func _tile(name: String, main := false) -> Control:
	var entry: Dictionary = entries.get(name, {})
	var button := Button.new()
	button.name = "tile_" + name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.custom_minimum_size = Vector2(150, 54 if not main else 64)
	var v := _values(name)
	var label := str(entry.get("label", "")) if str(entry.get("label", "")) != "" else name.replace("_", " ")
	var text := label
	var colour := Palette.MUTED
	if v[0] != null:
		text += "\n" + fmt.value(entry, v[0], true, false)
		if v[1] != null and typeof(v[0]) != TYPE_BOOL:
			var d := float(v[0]) - float(v[1])
			if d != 0.0:
				text += "  " + fmt.change(entry, d)
				colour = Palette.GOOD if d > 0.0 else Palette.BAD
	else:
		var dims: Array = entry.get("dims", [])
		var where := str(entry.get("entity", ""))
		text += "\n" + ("by " + ", ".join(dims).replace("_", " ") if not dims.is_empty() else ("for each " + where if where != "" else str(entry.get("kind", ""))))
	button.text = text
	button.tooltip_text = str(entry.get("doc", ""))
	var style := Palette.panel_style(Palette.PANEL_RAISED, 0, 6)
	style.border_color = Palette.ACCENT if main else colour
	style.set_border_width_all(2 if main else 1)
	button.add_theme_stylebox_override("normal", style)
	if not main:
		button.pressed.connect(func() -> void: show_value(name))
	return button
