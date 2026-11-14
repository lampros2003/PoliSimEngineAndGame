extends PanelContainer
## The government's budget, generated from the model: every payment into the government
## sector is revenue, every payment out is spending. This month, last month, the change,
## and buttons to chart a line or ask why it moved.

const Palette := preload("res://scripts/palette.gd")

signal chart_requested(row: String, label: String)
signal explain_requested(name: String)

var fmt: RefCounted
var _grid: GridContainer
var _title: Label
var _lines: Array = []  # {name, row, entry, labels: [this, last, change], sign}
var _totals := {}  # "revenue" / "spending" / "balance" -> [this, last, change]
var _sector := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.text = "Budget"
	_title.add_theme_font_size_override("font_size", Palette.TITLE)
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 6
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
		label.custom_minimum_size = Vector2(118, 0)
	return label


func _section(title: String) -> void:
	_grid.add_child(_cell(title, Palette.MUTED, false, Palette.SMALL))
	for i in 5:
		_grid.add_child(Control.new())


func _line(name: String, entry: Dictionary, sign: int) -> void:
	var label := _cell(str(entry.get("label", name)), Palette.TEXT, false)
	label.tooltip_text = str(entry.get("doc", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size = Vector2(200, 0)
	_grid.add_child(label)
	var cells := [_cell("–"), _cell("–", Palette.MUTED), _cell("–")]
	for c in cells:
		_grid.add_child(c)
	var row: String = entry.get("row", name)
	var plot := Button.new()
	plot.text = "Chart"
	plot.name = "chart_" + name
	plot.pressed.connect(func() -> void: chart_requested.emit(row, str(entry.get("label", name))))
	_grid.add_child(plot)
	var why := Button.new()
	why.text = "Why"
	why.name = "why_" + name
	why.pressed.connect(func() -> void: explain_requested.emit(name))
	_grid.add_child(why)
	_lines.append({"name": name, "row": row, "entry": entry, "cells": cells, "sign": sign})


func _total(key: String, title: String) -> void:
	_grid.add_child(_cell(title, Palette.TEXT, false, Palette.FONT_SIZE))
	var cells := [_cell("–"), _cell("–", Palette.MUTED), _cell("–")]
	for c in cells:
		_grid.add_child(c)
	_grid.add_child(Control.new())
	_grid.add_child(Control.new())
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
	_title.text = "Budget of the %s, this month" % str(found["label"]).to_lower()
	for heading in ["", "This month", "Last month", "Change", "", ""]:
		_grid.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	_section("Revenue")
	for name in found["inflows"]:
		_line(name, entries.get(name, {}), 1)
	_total("revenue", "Total revenue")
	_section("Spending")
	for name in found["outflows"]:
		_line(name, entries.get(name, {}), -1)
	_total("spending", "Total spending")
	_section("")
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
	var money := {"money": true, "shown_unit": "", "type": "int"}
	for key in ["revenue", "spending"]:
		_show_total(key, sums[key], known[key], money, 1 if key == "revenue" else -1)
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


## Green when the budget improves (more revenue, less spending), red when it worsens.
static func _colour(now: Variant, before: Variant, sign: int) -> Color:
	if now == null or before == null or int(now) == int(before):
		return Palette.MUTED
	return Palette.GOOD if (int(now) - int(before)) * sign > 0 else Palette.BAD
