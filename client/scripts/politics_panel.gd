extends PanelContainer
## Politics (stage S5.5): the polls, the House of Commons by bloc, the next election. All
## from the scenario's `[play.politics]` table, which names the model's values: voting
## intention, seats and the projection by bloc, which blocs govern, the government's poll
## rating, turnout, the election flag and the months to the next election; and (stage S8.3)
## the issues voters weigh, each against where it stood at the last election.

const Palette := preload("res://scripts/palette.gd")

## One colour per bloc, in the dimension's order.
const BLOC_COLOURS := [Color("#d6534f"), Color("#4f86d6"), Color("#e8a948"), Color("#3fb5c4"), Color("#5cbf7a"),
	Color("#e8d548"), Color("#4fa36b"), Color("#a98ee0"), Color("#94a0ab"), Color("#c47a9b")]

var fmt: RefCounted
var settings := {}
var _summary: Label
var _issues: Label
var _election: Label
var _bar: Control
var _grid: GridContainer
var _rows: Array = []  # per bloc: {cells: [name, polls, change, seats, projected]}
var _seats := PackedFloat64Array()
var _governing := PackedFloat64Array()


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Politics"
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_election = Label.new()
	_election.add_theme_color_override("font_color", Palette.MUTED)
	top.add_child(_election)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(600, 0)
	box.add_child(_summary)
	_issues = Label.new()
	_issues.name = "issues"
	_issues.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_issues.custom_minimum_size = Vector2(600, 0)
	_issues.add_theme_color_override("font_color", Palette.MUTED)
	_issues.visible = false
	box.add_child(_issues)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(600, 22)
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 9)
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
		label.custom_minimum_size = Vector2(90, 0)
	return label


## Shows the panel when the scenario has a [play.politics] table.
func build(play: Dictionary) -> void:
	settings = play.get("politics", {})
	visible = not settings.is_empty()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_rows.clear()


func _ensure_rows(labels: PackedStringArray) -> void:
	if _rows.size() == labels.size():
		return
	for heading in ["", "Polls", "Change", "Seats", "If held now"]:
		_grid.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	for i in labels.size():
		var swatch := HBoxContainer.new()
		swatch.add_theme_constant_override("separation", 6)
		var dot := ColorRect.new()
		dot.color = BLOC_COLOURS[i % BLOC_COLOURS.size()]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_child(dot)
		var name := _cell(labels[i], Palette.TEXT, false)
		name.custom_minimum_size = Vector2(190, 0)
		swatch.add_child(name)
		_grid.add_child(swatch)
		var cells := [name, _cell("–"), _cell("–", Palette.MUTED), _cell("–"), _cell("–", Palette.MUTED)]
		for c in cells.slice(1):
			_grid.add_child(c)
		_rows.append({"swatch": swatch, "cells": cells})


## `cells_of(name)` is the bridge's cells(); `latest` and `previous` read result rows.
func refresh(cells_of: Callable, latest: Callable, previous: Callable, months_done: int) -> void:
	if settings.is_empty():
		return
	var intention: Dictionary = cells_of.call(str(settings.get("intention", "")))
	var seats: Dictionary = cells_of.call(str(settings.get("seats", "")))
	var projected: Dictionary = cells_of.call(str(settings.get("projected", "")))
	var governing: Dictionary = cells_of.call(str(settings.get("governing", "")))
	var labels: PackedStringArray = intention.get("labels", PackedStringArray())
	var months: Variant = latest.call(str(settings.get("months_to_election", "")))
	if months != null:
		var when: int = months_done - 1 + int(months)  # the month the election falls in
		_election.text = "Next general election: %s, in %d months" % [fmt.month_name(when), int(months)] if int(months) > 0 \
			else "A general election was held this month"
	if labels.is_empty():
		_summary.text = "The polls appear after the first month."
		return
	_ensure_rows(labels)
	var now: PackedFloat64Array = intention.get("values", PackedFloat64Array())
	var before: PackedFloat64Array = intention.get("previous", PackedFloat64Array())
	_seats = seats.get("values", PackedFloat64Array())
	_governing = governing.get("values", PackedFloat64Array())
	var held_now: PackedFloat64Array = projected.get("values", PackedFloat64Array())
	var total := 0.0
	for s in _seats:
		total += s
	var government := PackedStringArray()
	var government_seats := 0.0
	for i in labels.size():
		var line: Dictionary = _rows[i]
		var cells: Array = line["cells"]
		var in_government := i < _governing.size() and _governing[i] > 0.5
		var seat_count := _seats[i] if i < _seats.size() else 0.0
		var share := now[i] if i < now.size() else 0.0
		line["swatch"].visible = share >= 0.005 or seat_count > 0.0
		for c in cells.slice(1):
			c.visible = line["swatch"].visible
		cells[0].add_theme_color_override("font_color", Palette.ACCENT if in_government else Palette.TEXT)
		cells[0].tooltip_text = "In government" if in_government else ""
		cells[1].text = fmt.percent(share)
		if i < before.size():
			var d := (share - before[i]) * 100.0
			cells[2].text = "0.0" if absf(d) < 0.05 else ("+" if d > 0.0 else "−") + "%.1f" % absf(d)
		else:
			cells[2].text = "–"
		cells[3].text = "%d" % int(seat_count)
		cells[4].text = "%d" % int(held_now[i]) if i < held_now.size() else "–"
		if in_government:
			government.append(labels[i])
			government_seats += seat_count
	var majority := int(settings.get("majority", int(total / 2.0) + 1))
	var support: Variant = latest.call(str(settings.get("support", "")))
	var support_before: Variant = previous.call(str(settings.get("support", "")))
	var turnout: Variant = latest.call(str(settings.get("turnout", "")))
	var text := "Government: %s, %d of %d seats (%d needed for a majority)." % [
		_listed(government) if not government.is_empty() else "none", int(government_seats), int(total), majority]
	if support != null:
		text += " Its poll rating: %s" % fmt.percent(float(support))
		if support_before != null:
			var d := (float(support) - float(support_before)) * 100.0
			text += " (%s%.1f points on last month)" % ["+" if d >= 0.0 else "−", absf(d)]
		text += "."
	if turnout != null:
		text += " Turnout if an election were held now: %s." % fmt.percent(float(turnout))
	_summary.text = text
	_show_issues(cells_of)
	_bar.set_meta("majority", majority)
	_bar.queue_redraw()


## Stage S8.3: "What voters weigh, against the last election: Health −8%, ...", from the
## measures named by `issues` and `issues_at_election` (1 where things stood).
func _show_issues(cells_of: Callable) -> void:
	var now: Dictionary = cells_of.call(str(settings.get("issues", "")))
	var then: Dictionary = cells_of.call(str(settings.get("issues_at_election", "")))
	var labels: PackedStringArray = now.get("labels", PackedStringArray())
	var values: PackedFloat64Array = now.get("values", PackedFloat64Array())
	var before: PackedFloat64Array = then.get("values", PackedFloat64Array())
	_issues.visible = not labels.is_empty() and values.size() == labels.size() and before.size() == labels.size()
	if not _issues.visible:
		return
	var parts := PackedStringArray()
	for i in labels.size():
		if before[i] <= 0.0:
			parts.append("%s –" % labels[i])
			continue
		var d := (values[i] / before[i] - 1.0) * 100.0
		parts.append("%s %s%.1f%%" % [labels[i], "+" if d >= 0.0 else "−", absf(d)])
	_issues.text = "What voters weigh, against the last election: " + ", ".join(parts) + "."
	_issues.tooltip_text = "Health, education and policing: real spending per person served. The environment: the path to net zero over actual emissions. A fall costs the government votes, most among the age groups that care most."


## "A", "A and B", "A, B and C".
static func _listed(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## The House of Commons as one bar: each bloc's seats in its colour, the governing blocs
## first, and a line at the majority.
func _draw_bar() -> void:
	var total := 0.0
	for s in _seats:
		total += s
	if total <= 0.0:
		return
	var width := _bar.size.x
	var x := 0.0
	var order := []
	for i in _seats.size():
		if i < _governing.size() and _governing[i] > 0.5:
			order.append(i)
	for i in _seats.size():
		if not (i < _governing.size() and _governing[i] > 0.5):
			order.append(i)
	for i in order:
		var w := _seats[i] / total * width
		_bar.draw_rect(Rect2(x, 2, w, _bar.size.y - 4), BLOC_COLOURS[i % BLOC_COLOURS.size()])
		x += w
	var majority := float(_bar.get_meta("majority", total / 2.0))
	var m := majority / total * width
	_bar.draw_line(Vector2(m, 0), Vector2(m, _bar.size.y), Palette.TEXT, 2.0)


## Election night: the new House against the last one, as bbcode for a dialog.
func election_report(cells_of: Callable, player_governs: bool) -> String:
	var seats: Dictionary = cells_of.call(str(settings.get("seats", "")))
	var governing: Dictionary = cells_of.call(str(settings.get("governing", "")))
	var intention: Dictionary = cells_of.call(str(settings.get("intention", "")))
	var labels: PackedStringArray = seats.get("labels", PackedStringArray())
	var now: PackedFloat64Array = seats.get("values", PackedFloat64Array())
	var before: PackedFloat64Array = seats.get("previous", PackedFloat64Array())
	var votes: PackedFloat64Array = intention.get("values", PackedFloat64Array())
	var gov: PackedFloat64Array = governing.get("values", PackedFloat64Array())
	var lines := PackedStringArray(["[b]The general election[/b]\n", "[table=4][cell][b]Bloc[/b]   [/cell][cell][b]Votes[/b]   [/cell][cell][b]Seats[/b]   [/cell][cell][b]Change[/b][/cell]"])
	var government := PackedStringArray()
	for i in labels.size():
		var n := int(now[i]) if i < now.size() else 0
		var was := int(before[i]) if i < before.size() else n
		if n == 0 and was == 0:
			continue
		var change := n - was
		lines.append("[cell]%s   [/cell][cell]%s   [/cell][cell]%d   [/cell][cell]%s[/cell]" % [labels[i],
			fmt.percent(votes[i]) if i < votes.size() else "–", n, ("+%d" % change) if change > 0 else ("−%d" % -change if change < 0 else "no change")])
		if i < gov.size() and gov[i] > 0.5:
			government.append(labels[i])
	lines.append("[/table]\n")
	lines.append("The new government: %s." % _listed(government))
	if player_governs:
		lines.append("\n[b]You remain in office.[/b]")
	else:
		lines.append("\n[b]Your government has lost office. The game is over[/b]: load your save to try again.")
	return "\n".join(lines)
