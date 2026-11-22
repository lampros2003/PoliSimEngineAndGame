extends PanelContainer
## The government's budget, generated from the model: every payment into the government
## sector is revenue, every payment out is spending. This month, last month and the change.
## Stage S13.2: the ledger of the Budget sheet; every line opens its popup.

const Palette := preload("res://scripts/palette.gd")

## A line was pressed: its entry's name, and where on screen, for the popup to grow from.
signal line_pressed(name: String, origin: Rect2)

var fmt: RefCounted
var _grid: GridContainer
var _title: Label
var _lines: Array = []  # {name, row, entry, labels: [this, last, change], sign}
var _totals := {}  # "revenue" / "spending" / "balance" -> [this, last, change]
var _sector := ""
var _summary: Control
var _sums := [0.0, 0.0]  # revenue and spending this month, for the bars


func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.text = "Budget"
	_title.theme_type_variation = "Muted"
	box.add_child(_title)
	# Stage S13.2: revenue against spending as two printed bars, the gap between them named.
	_summary = Control.new()
	_summary.custom_minimum_size = Vector2(0, 104)
	_summary.draw.connect(_draw_summary)
	box.add_child(_summary)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 4)  # stage S14.1: the whole ledger on a 1080p screen
	Palette.rule_rows(_grid)
	box.add_child(_grid)


func _cell(text: String, color := Palette.TEXT, right := true, size := Palette.FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	if size == Palette.SMALL:
		label.theme_type_variation = "Heading"
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size = Vector2(130, 0)
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the names take the room left, the figures to the right
	return label


## Stage S17.1: a heading or a total in the names' column, its words starting where the lines'
## do: a line is a link with 4 px inside its left edge, so these stand 4 px in, by the layout
## (two spaces did it before, and put the totals 3 px off the lines).
func _in_names(label: Label) -> MarginContainer:
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 4)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(label)
	return inset


func _section(title: String) -> void:
	_grid.add_child(_in_names(_cell(title, Palette.MUTED, false, Palette.SMALL)))
	for i in 3:
		_grid.add_child(Control.new())


func _line(name: String, entry: Dictionary, sign: int) -> void:
	var label := Button.new()
	label.name = "line_" + name
	label.text = str(entry.get("label", name))
	label.tooltip_text = str(entry.get("doc", ""))
	label.theme_type_variation = "LinkRow"
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE)
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(260, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.pressed.connect(func() -> void: line_pressed.emit(name, label.get_global_rect()))
	_grid.add_child(label)
	var cells := [_cell("–"), _cell("–", Palette.MUTED), _cell("–")]
	for c in cells:
		_grid.add_child(c)
	var row: String = entry.get("row", name)
	_lines.append({"name": name, "row": row, "entry": entry, "cells": cells, "sign": sign, "button": label})

func _total(key: String, title: String) -> void:
	var total := _cell(title, Palette.TEXT, false, Palette.FONT_SIZE)
	total.name = "total_" + key
	total.add_theme_font_override("font", Palette.text(600))
	_grid.add_child(_in_names(total))
	var cells := [_cell("–"), _cell("–", Palette.MUTED), _cell("–")]
	for c in cells:
		_grid.add_child(c)
	_totals[key] = cells


func build(catalogue: Dictionary, entries: Dictionary, sector: String) -> void:
	for child in _grid.get_children():
		child.queue_free()
	_lines.clear()
	_totals.clear()
	_sector = sector
	var found := {}
	for s in catalogue.get("sectors", []):
		if s["name"] == sector:
			found = s
	if found.is_empty():
		_title.text = "Budget (no sector named %s in this model)" % sector
		return
	_title.text = "The %s's money this month%s" % [str(found["label"]).to_lower(), ", at an annual rate" if fmt.per_year else ""]
	for heading in ["", "This month", "Last month", "Change"]:
		_grid.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	# Only payments count: not purchases or sales of assets (marked financial in the
	# model), and nothing in an instrument other than the one payments use.
	var instruments: PackedStringArray = catalogue.get("instruments", PackedStringArray())
	var payments := instruments[0] if instruments.size() > 0 else ""
	var counts := func(name: String) -> bool:
		var e: Dictionary = entries.get(name, {})
		return not e.get("financial", false) and str(e.get("instrument", payments)) == payments
	_section("Revenue")
	for name in found["inflows"]:
		if counts.call(name):
			_line(name, entries.get(name, {}), 1)
	_total("revenue", "Total revenue")
	_section("Spending")
	for name in found["outflows"]:
		if counts.call(name):
			_line(name, entries.get(name, {}), -1)
	_total("spending", "Total spending")
	_total("balance", "Surplus or deficit")


func refresh(latest: Callable, previous: Callable) -> void:
	var sums := {"revenue": [0, 0], "spending": [0, 0]}
	var known := {"revenue": [true, true], "spending": [true, true]}
	for line in _lines:
		var now: Variant = latest.call(line["row"])
		var before: Variant = previous.call(line["row"])
		var entry: Dictionary = line["entry"]
		var cells: Array = line["cells"]
		cells[0].text = fmt.value(entry, now, true, false)
		cells[1].text = fmt.value(entry, before, true, false)
		cells[2].text = fmt.change(entry, int(now) - int(before)) if now != null and before != null else "–"
		cells[2].add_theme_color_override("font_color", _colour(now, before, line["sign"]))
		var key := "revenue" if line["sign"] > 0 else "spending"
		for i in 2:
			var v: Variant = now if i == 0 else before
			if v == null:
				known[key][i] = false
			else:
				sums[key][i] += int(v)
	var money := {"money": true, "shown_unit": "%s/%s" % [fmt.currency, fmt.step_unit], "type": "int"}
	for key in ["revenue", "spending"]:
		_show_total(key, sums[key], known[key], money, 1 if key == "revenue" else -1)
	_sums = [float(sums["revenue"][0]), float(sums["spending"][0])] if known["revenue"][0] and known["spending"][0] else [0.0, 0.0]
	_summary.queue_redraw()
	var balance := [sums["revenue"][0] - sums["spending"][0], sums["revenue"][1] - sums["spending"][1]]
	var balance_known := [known["revenue"][0] and known["spending"][0], known["revenue"][1] and known["spending"][1]]
	_show_total("balance", balance, balance_known, money, 1)
	var cells: Array = _totals.get("balance", [])
	if cells.size() == 3 and balance_known[0]:
		cells[0].add_theme_color_override("font_color", Palette.GOOD if balance[0] >= 0 else Palette.BAD)


func _show_total(key: String, values: Array, known: Array, entry: Dictionary, sign: int) -> void:
	var cells: Array = _totals.get(key, [])
	if cells.size() != 3:
		return
	cells[0].text = fmt.value(entry, values[0], true, false) if known[0] else "–"
	cells[1].text = fmt.value(entry, values[1], true, false) if known[1] else "–"
	if known[0] and known[1]:
		cells[2].text = fmt.change(entry, values[0] - values[1])
		cells[2].add_theme_color_override("font_color", _colour(values[0], values[1], sign))
	else:
		cells[2].text = "–"


func _draw_summary() -> void:
	var top: float = maxf(_sums[0], _sums[1])
	if top <= 0.0:
		return
	var money := {"money": true, "shown_unit": "%s/%s" % [fmt.currency, fmt.step_unit], "type": "int"}
	var caps := Palette.display(600, 1)
	var figure := Palette.display(500)
	var width := _summary.size.x - 300.0
	for i in 2:
		var y := 8.0 + i * 46.0
		var w: float = width * _sums[i] / top
		var colour: Color = Palette.BLUE if i == 0 else Palette.BRICK
		_summary.draw_string(caps, Vector2(0, y + 24.0), ["REVENUE", "SPENDING"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPS, Palette.MUTED)
		_summary.draw_rect(Rect2(100.0 + 4.0, y + 4.0, w, 30.0), Palette.SHADOW)
		_summary.draw_rect(Rect2(100.0, y, w, 30.0), colour)
		# Stage S13.4: each total in a column past both bars, so neither bar's end line crosses it.
		_summary.draw_string(figure, Vector2(116.0 + width, y + 24.0), fmt.value(money, int(_sums[i]), true, false), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.INK)
	var gap: float = _sums[0] - _sums[1]
	var x: float = 100.0 + width * minf(_sums[0], _sums[1]) / top
	var x2: float = 100.0 + width * maxf(_sums[0], _sums[1]) / top
	_summary.draw_line(Vector2(x, 2.0), Vector2(x, 92.0), Palette.INK, 1.5)
	_summary.draw_line(Vector2(x2, 2.0), Vector2(x2, 92.0), Palette.INK, 1.5)
	var words: String = ("SURPLUS " if gap >= 0.0 else "DEFICIT ") + fmt.value(money, int(absf(gap)), true, false)
	_summary.draw_string(caps, Vector2(x2 + 12.0, 98.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPS, Palette.GOOD if gap >= 0.0 else Palette.BAD)


## Green when the budget improves (more revenue, less spending), red when it worsens.
static func _colour(now: Variant, before: Variant, sign: int) -> Color:
	if now == null or before == null or int(now) == int(before):
		return Palette.MUTED
	return Palette.GOOD if (int(now) - int(before)) * sign > 0 else Palette.BAD
