extends PanelContainer
## Who gains, who loses: a value broken down by a dimension (income decile, household
## type, region), this month, with each group's change on last month drawn as a bar.
## The breakdowns are the scenario's `[play] breakdowns`; `breakdown_all` names the
## national value they average to, shown as the last line.

const Palette := preload("res://scripts/palette.gd")
const Format := preload("res://scripts/format.gd")
const Bar := preload("res://scripts/bar.gd")

var fmt: RefCounted
var _choice: OptionButton
var _grid: GridContainer
var _note: Label
var _names: Array = []  # breakdown value names, parallel to the choice's items
var _entries := {}
var _all := ""  # row of the national value, or ""
var _rows: Array = []  # {cells: [label, now, change, percent], bar}
var _all_cells: Array = []
var _all_bar: Control
var _source: Array = []  # [cells_of, latest, previous] from the last refresh


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var title := Label.new()
	title.text = "Who gains, who loses"
	title.add_theme_font_size_override("font_size", Palette.TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_choice = OptionButton.new()
	_choice.name = "breakdown_choice"
	_choice.item_selected.connect(func(_i: int) -> void:
		_clear()
		if _source.size() == 3:
			refresh(_source[0], _source[1], _source[2]))
	top.add_child(_choice)
	_note = Label.new()
	_note.add_theme_color_override("font_color", Palette.MUTED)
	_note.add_theme_font_size_override("font_size", Palette.SMALL)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(600, 0)
	box.add_child(_note)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)


func _cell(text: String, color := Palette.TEXT, right := true, size := Palette.FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size = Vector2(100, 0)
	return label


## Shows the panel when the scenario names breakdowns the model has; hides it otherwise.
func build(play: Dictionary, entries: Dictionary) -> void:
	_entries = entries
	var keep := selected()
	_names.clear()
	_choice.clear()
	for name in play.get("breakdowns", []):
		var entry: Dictionary = entries.get(str(name), {})
		if entry.is_empty() or (entry.get("dims", []) as Array).size() != 1:
			continue
		_names.append(str(name))
		_choice.add_item(_short_label(entry))
		if str(name) == keep:
			_choice.select(_names.size() - 1)
	var all: Dictionary = entries.get(str(play.get("breakdown_all", "")), {})
	_all = str(all.get("row", ""))
	visible = not _names.is_empty()
	_choice.visible = _names.size() > 1
	_clear()


## "Net income per household, by income decile" gives "By income decile".
static func _short_label(entry: Dictionary) -> String:
	var label := str(entry.get("label", entry.get("name", "")))
	var comma := label.rfind(", ")
	if comma < 0:
		return label
	var tail := label.substr(comma + 2)
	return tail.left(1).to_upper() + tail.substr(1)


func selected() -> String:
	var i := _choice.selected
	return _names[i] if i >= 0 and i < _names.size() else ""


func _clear() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_rows.clear()
	_all_cells.clear()
	_note.text = ""


## The rows follow the cells: one per member of the value's dimension.
func _build_rows(entry: Dictionary, labels: PackedStringArray) -> void:
	_clear()
	var label := str(entry.get("label", ""))
	var comma := label.rfind(", ")
	_note.text = "%s, %s. Each group's average over the simulated households in it; the bar is its change on last month." % [
		label.substr(0, comma) if comma >= 0 else label, "at an annual rate" if fmt.per_year else "a month"]
	for heading in ["", "This month", "Change", "", ""]:
		_grid.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	for member in labels:
		_rows.append(_row(member, Palette.TEXT))
	if _all != "":
		var line := _row("All households", Palette.ACCENT)
		_all_cells = line["cells"]
		_all_bar = line["bar"]


func _row(text: String, colour: Color) -> Dictionary:
	var cells := [_cell(text, colour, false), _cell("–"), _cell("–"), _cell("", Palette.MUTED)]
	cells[0].custom_minimum_size = Vector2(190, 0)
	for c in cells:
		_grid.add_child(c)
	var bar := Bar.new()
	_grid.add_child(bar)
	return {"cells": cells, "bar": bar}


## `cells_of(name)` is the bridge's cells(); `latest` and `previous` read result rows.
func refresh(cells_of: Callable, latest: Callable, previous: Callable) -> void:
	_source = [cells_of, latest, previous]
	var name := selected()
	if name == "":
		return
	var entry: Dictionary = _entries[name]
	var data: Dictionary = cells_of.call(name)
	var labels: PackedStringArray = data.get("labels", PackedStringArray())
	var now: PackedFloat64Array = data.get("values", PackedFloat64Array())
	if labels.is_empty() or now.size() != labels.size():
		if _rows.is_empty():
			_note.text = "Shown from the first month."
		for line in _rows:
			for c in (line["cells"] as Array).slice(1):
				c.text = "–"
		return
	if _rows.size() != labels.size():
		_build_rows(entry, labels)
	var before: PackedFloat64Array = data.get("previous", PackedFloat64Array())
	var shares := []
	var widest := 0.005  # a bar's full width is at least a 0.5% change
	for i in labels.size():
		var share: Variant = null
		if i < before.size() and before[i] != 0.0:
			share = now[i] / before[i] - 1.0
			widest = maxf(widest, absf(share))
		shares.append(share)
	for i in labels.size():
		var line: Dictionary = _rows[i]
		var was: Variant = before[i] if i < before.size() else null
		_show(line["cells"], entry, now[i], was, shares[i])
		line["bar"].fraction = 0.0 if shares[i] == null else shares[i] / widest
		line["bar"].queue_redraw()
	if _all_cells.size() == 4:
		var a: Variant = latest.call(_all)
		var b: Variant = previous.call(_all)
		var share: Variant = null
		if a != null and b != null and float(b) != 0.0:
			share = float(a) / float(b) - 1.0
		_show(_all_cells, entry, a, b, share)
		_all_bar.fraction = 0.0 if share == null else share / maxf(widest, absf(share))
		_all_bar.queue_redraw()


func _show(cells: Array, entry: Dictionary, now: Variant, before: Variant, share: Variant) -> void:
	cells[1].text = fmt.value(entry, now, false, false)
	if now == null or before == null:
		cells[2].text = "–"
		cells[3].text = ""
		cells[2].add_theme_color_override("font_color", Palette.MUTED)
		return
	cells[2].text = fmt.change(entry, float(now) - float(before))
	cells[3].text = "" if share == null else ("+" if share >= 0.0 else Format.MINUS) + "%.2f%%" % (absf(share) * 100.0)
	var colour := Palette.MUTED
	if share != null and absf(share) >= 0.00005:
		colour = Palette.GOOD if share > 0.0 else Palette.BAD
	cells[2].add_theme_color_override("font_color", colour)
