extends PanelContainer
## Politics (stage S5.5): the polls, the House of Commons by bloc, the next election. All
## from the scenario's `[play.politics]` table, which names the model's values: voting
## intention, seats and the projection by bloc, which blocs govern, the government's poll
## rating, turnout, the election flag and the months to the next election; and (stage S8.3)
## the issues voters weigh, each against where it stood at the last election. Stage S13.2:
## the Parliament sheet, with the House drawn as rows of seats, one dot each. Stage S13.4:
## the country by group, each group's share, approval and month's change; a row opens the
## group's popup.

const Palette := preload("res://scripts/palette.gd")

## One colour per bloc, in the dimension's order.
## Stage S17.1: each at least 3 to 1 against card stock (the gold, the yellow and the grey were
## under it), so a bloc's seats can be told from the sheet they are printed on.
const BLOC_COLOURS := [Color("#b0412c"), Color("#1f4e79"), Color("#b58121"), Color("#3d8a8f"), Color("#5f7f55"),
	Color("#9a8c2e"), Color("#2e5e44"), Color("#76609a"), Color("#878b92"), Color("#a3586f")]
## Seats per column of the House.
const SEAT_ROWS := 10

## A group's row was pressed: its board key, and where on screen.
signal group_pressed(key: String, origin: Rect2)

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
var _groups_fold: Control
## Stage S15.3: the four stances ([play.web] stances), each a scale; and the country by place
## ([play.web] places). For the checks: the stances shown, as {item, value, words, control}.
var stance_rows: Array = []
var _stances: VBoxContainer
var _stances_fold: Control
var _places: GridContainer
var _places_fold: Control
var _place_rows: Array = []
## Group key -> {label, row, approval}, for the ends of the stances' scales; and what moved a
## stance last: stance row -> words (set by the screen).
var group_info := {}
var last_moved := {}
var _groups: GridContainer
var _group_rows: Array = []  # {key, row, share, note, cells: [share, bar, approval, change]}


func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_election = Label.new()
	_election.add_theme_font_override("font", Palette.display(500))
	_election.add_theme_font_size_override("font_size", 20)
	top.add_child(_election)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(560, 0)
	box.add_child(_summary)
	_issues = Label.new()
	_issues.name = "issues"
	_issues.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_issues.custom_minimum_size = Vector2(560, 0)
	_issues.add_theme_color_override("font_color", Palette.MUTED)
	_issues.visible = false
	box.add_child(_issues)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(600, 150)
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 4)
	Palette.rule_rows(_grid)
	# Stage S14.1: the parties and the groups open one at a time, so the sheet fits the screen.
	var folds := VBoxContainer.new()
	folds.add_theme_constant_override("separation", 8)
	box.add_child(folds)
	folds.add_child(Palette.fold("The parties", _grid))
	_stances = VBoxContainer.new()
	_stances.name = "stances"
	_stances.add_theme_constant_override("separation", 12)
	_stances_fold = Palette.fold("Where the government stands", _stances, true)
	_stances_fold.visible = false
	folds.add_child(_stances_fold)
	_groups = GridContainer.new()
	_groups.name = "groups"
	_groups.columns = 5
	_groups.add_theme_constant_override("h_separation", 16)
	_groups.add_theme_constant_override("v_separation", 4)
	Palette.rule_rows(_groups)
	_groups_fold = Palette.fold("The country by group", _groups)
	folds.add_child(_groups_fold)
	_places = GridContainer.new()
	_places.name = "places"
	_places.columns = 5
	_places.add_theme_constant_override("h_separation", 16)
	_places.add_theme_constant_override("v_separation", 4)
	Palette.rule_rows(_places)
	_places_fold = Palette.fold("The country by place", _places)
	_places_fold.visible = false
	folds.add_child(_places_fold)


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
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Shows the panel when the scenario has a [play.politics] table.
func build(play: Dictionary) -> void:
	settings = play.get("politics", {})
	visible = not settings.is_empty()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_rows.clear()


## Stage S13.4: a row per interest group on the board. Stage S15.3: and the stances and the
## places the scenario's [play.web] gives (`web`).
func build_groups(board: Control, web := {}) -> void:
	_build_stances(web.get("stances", []))
	# Stage S15.3: the stances open first where there are any (the House above shows the
	# parties); else the parties' table.
	if web.get("stances", []).is_empty():
		var parties: Node = _grid.get_parent()
		if parties != null and parties.has_meta("fold"):
			(parties.get_meta("fold") as Callable).call(true)
		_stances_fold.get_meta("fold").call(false)
	_build_places(web.get("places", []))
	_build_ring_groups(board)


func _build_ring_groups(board: Control) -> void:
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	_group_rows.clear()
	var keys: PackedStringArray = board.keys_of("group")
	_groups_fold.visible = not keys.is_empty()
	if keys.is_empty():
		return
	for heading in ["", "Share of adults", "Backing the government", "", "Last month"]:
		_groups.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	group_info.clear()
	for key in keys:
		group_info[key.trim_prefix("group:")] = {"label": str(board.nodes[key]["label"]), "row": str(board.nodes[key]["row"]), "approval": ""}
	for key in keys:
		var node: Dictionary = board.nodes[key]
		var name := Button.new()
		name.name = "group_" + key.trim_prefix("group:")
		name.text = str(node["label"])
		name.theme_type_variation = "LinkRow"
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.custom_minimum_size = Vector2(190, 0)
		name.pressed.connect(func() -> void: group_pressed.emit(key, name.get_global_rect()))
		_groups.add_child(name)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.draw.connect(func() -> void: _draw_approval(bar))
		var cells := [_cell("–"), bar, _cell("–"), _cell("–", Palette.MUTED)]
		for c in cells:
			_groups.add_child(c)
		_group_rows.append({"key": key, "row": str(node["row"]), "share": str(node.get("share", "")), "note": str(node.get("note", "")),
			"button": name, "cells": cells})


## Stage S15.3: the stances: each a labelled scale, its ends named with their belief groups.
func _build_stances(list: Array) -> void:
	for child in _stances.get_children():
		_stances.remove_child(child)
		child.queue_free()
	stance_rows.clear()
	_stances_fold.visible = not list.is_empty()
	for item in list:
		var scale := Control.new()
		scale.name = "stance_" + str(item.get("row", ""))
		scale.custom_minimum_size = Vector2(0, 78)
		var info := {"item": item, "value": 0.0, "control": scale, "words": ""}
		scale.draw.connect(func() -> void: _draw_stance(scale, info))
		_stances.add_child(scale)
		stance_rows.append(info)
	if not list.is_empty():
		var note := Label.new()
		note.text = "Each scale counts the government's clear moves of policy since 2024, net; the marker is where it stands now. The groups at its ends answer to it."
		note.theme_type_variation = "Muted"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 560
		_stances.add_child(note)


## Stage S15.3: one stance: its name, and what moved it last, above; a line with ticks and
## nought in the middle; the marker where the government stands; each end's words and group.
func _draw_stance(c: Control, info: Dictionary) -> void:
	var item: Dictionary = info["item"]
	var w := c.size.x
	var head := Palette.display(600, 1)
	var body := Palette.text(500)
	var strong := Palette.text(600)
	c.draw_string(head, Vector2(0, 14), str(item.get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPS, Palette.INK)
	if str(info["words"]) != "":
		c.draw_string(body, Vector2(0, 14), str(info["words"]), HORIZONTAL_ALIGNMENT_RIGHT, w, Palette.SMALL, Palette.MUTED)
	var value := float(info["value"])
	var span := maxf(3.0, ceilf(absf(value) * 1.2))
	var x0 := 180.0
	var x1 := w - 210.0
	var y := 42.0
	c.draw_line(Vector2(x0, y), Vector2(x1, y), Palette.INK, 2.0)
	for k in range(-int(span), int(span) + 1):
		var x := lerpf(x0, x1, (float(k) + span) / (2.0 * span))
		c.draw_line(Vector2(x, y - (7.0 if k == 0 else 4.0)), Vector2(x, y + (7.0 if k == 0 else 4.0)), Palette.INK if k == 0 else Color(Palette.INK, 0.5), 1.5 if k == 0 else 1.0)
	var mx := lerpf(x0, x1, (clampf(value, -span, span) + span) / (2.0 * span))
	var marker := PackedVector2Array([Vector2(mx, y - 3), Vector2(mx - 9, y - 18), Vector2(mx + 9, y - 18)])
	c.draw_colored_polygon(marker, Palette.OCHRE)
	marker.append(marker[0])
	c.draw_polyline(marker, Palette.INK, 1.5, true)
	for end in ["low", "high"]:
		var words := str(item.get(end, ""))
		var group := str(item.get(end + "_group", ""))
		var who := ""
		if group_info.has(group):
			who = str(group_info[group]["label"]) + ("  " + str(group_info[group]["approval"]) if str(group_info[group]["approval"]) != "" else "")
		var x := 0.0 if end == "low" else x1 + 14.0
		var width := x0 - 14.0 if end == "low" else w - x
		var align := HORIZONTAL_ALIGNMENT_RIGHT if end == "low" else HORIZONTAL_ALIGNMENT_LEFT
		c.draw_string(strong, Vector2(x, y + 5), words, align, width, Palette.SMALL, Palette.INK)
		if who != "":
			c.draw_string(body, Vector2(x, y + 24), who, align, width, Palette.SMALL, Palette.MUTED)
	c.draw_string(body, Vector2(x0, y + 28), "0.0" if absf(value) < 0.05 else ("+" if value > 0.0 else "−") + "%.1f" % absf(value), HORIZONTAL_ALIGNMENT_CENTER, x1 - x0, Palette.SMALL, Palette.MUTED)


## Stage S15.3: the regions, off the ring: a row each, as in the groups' table.
func _build_places(list: Array) -> void:
	for child in _places.get_children():
		_places.remove_child(child)
		child.queue_free()
	_place_rows.clear()
	_places_fold.visible = not list.is_empty()
	if list.is_empty():
		return
	for heading in ["", "Share of adults", "Backing the government", "", "Last month"]:
		_places.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	for item in list:
		var name := _cell(str(item.get("label", "")), Palette.TEXT, false)
		name.custom_minimum_size = Vector2(190, 0)
		_places.add_child(name)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.draw.connect(func() -> void: _draw_approval(bar))
		var cells := [_cell("–"), bar, _cell("–"), _cell("–", Palette.MUTED)]
		for c in cells:
			_places.add_child(c)
		_place_rows.append({"row": str(item.get("row", "")), "share": str(item.get("share", "")), "note": str(item.get("note", "")), "cells": cells})


## A group's approval as a bar from nought to a half, with a tick at the national rating.
func _draw_approval(bar: Control) -> void:
	var v := float(bar.get_meta("approval", 0.0))
	var national := float(bar.get_meta("national", -1.0))
	var w := bar.size.x
	bar.draw_rect(Rect2(0, 3, w, bar.size.y - 6), Color(Palette.RULE, 0.5))
	bar.draw_rect(Rect2(0, 3, w * clampf(v / 0.5, 0.0, 1.0), bar.size.y - 6), Palette.BLUE)
	if national >= 0.0:
		var x := w * clampf(national / 0.5, 0.0, 1.0)
		bar.draw_line(Vector2(x, 0), Vector2(x, bar.size.y), Palette.INK, 2.0)


func _show_groups(latest: Callable, previous: Callable) -> void:
	var national: Variant = latest.call(str(settings.get("support", "")))
	for key in group_info:
		var a: Variant = latest.call(str(group_info[key]["row"]))
		group_info[key]["approval"] = fmt.percent(float(a)) if a != null else ""
	for info in stance_rows:
		var v: Variant = latest.call(str(info["item"].get("row", "")))
		info["value"] = float(v) if v != null else 0.0
		info["words"] = str(last_moved.get(str(info["item"].get("row", "")), ""))
		(info["control"] as Control).queue_redraw()
	for g in _group_rows + _place_rows:
		var cells: Array = g["cells"]
		var share: Variant = latest.call(g["share"]) if g["share"] != "" else null
		var now: Variant = latest.call(g["row"])
		var was: Variant = previous.call(g["row"])
		cells[0].text = fmt.percent(float(share)) if share != null else "–"
		var silent: bool = now != null and absf(float(now)) < 0.0005 and g["note"] != ""
		cells[1].set_meta("approval", 0.0 if now == null or silent else float(now))
		cells[1].set_meta("national", float(national) if national != null else -1.0)
		cells[1].tooltip_text = g["note"] if silent else ""
		cells[1].queue_redraw()
		cells[2].text = "–" if now == null or silent else fmt.percent(float(now))
		cells[2].tooltip_text = g["note"] if silent else ""
		cells[3].text = "–"
		cells[3].add_theme_color_override("font_color", Palette.MUTED)
		if now != null and was != null and not silent:
			var d := (float(now) - float(was)) * 100.0
			cells[3].text = "0.0" if absf(d) < 0.05 else ("▲ +%.1f" % d if d > 0.0 else "▼ −%.1f" % absf(d))
			if absf(d) >= 0.05:
				cells[3].add_theme_color_override("font_color", Palette.GOOD if d > 0.0 else Palette.BAD)


func _ensure_rows(labels: PackedStringArray) -> void:
	if _rows.size() == labels.size():
		return
	for heading in ["", "Polls", "Change", "Seats", "If held now"]:
		_grid.add_child(_cell(heading, Palette.MUTED, heading != "", Palette.SMALL))
	for i in labels.size():
		var swatch := HBoxContainer.new()
		swatch.add_theme_constant_override("separation", 8)
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
	_show_groups(latest, previous)
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
		# Stage S17.1: no signed noughts ("Health −0.0%").
		parts.append("%s %s%.1f%%" % [labels[i], "" if absf(d) < 0.05 else ("+" if d > 0.0 else "−"), absf(d)])
	_issues.text = "What voters weigh, against the last election: " + ", ".join(parts) + "."
	_issues.tooltip_text = "Health, education and policing: real spending per person served. The environment: the path to net zero over actual emissions. A fall costs the government votes, most among the age groups that care most."


## "A", "A and B", "A, B and C".
static func _listed(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## The House of Commons as rows of seats, one dot per seat, the governing blocs first,
## filled column by column so each bloc reads as a band; a rule marks the majority.
func _draw_bar() -> void:
	var total := 0.0
	for s in _seats:
		total += s
	if total <= 0.0:
		return
	var order := []
	for i in _seats.size():
		if i < _governing.size() and _governing[i] > 0.5:
			order.append(i)
	for i in _seats.size():
		if not (i < _governing.size() and _governing[i] > 0.5):
			order.append(i)
	var columns := ceili(total / SEAT_ROWS)
	var cell := minf(_bar.size.x / columns, (_bar.size.y - 26.0) / SEAT_ROWS)
	var r := cell * 0.38
	var seat := 0
	for i in order:
		for k in int(_seats[i]):
			var p := Vector2((seat / SEAT_ROWS + 0.5) * cell, (seat % SEAT_ROWS + 0.5) * cell)
			_bar.draw_circle(p, r, BLOC_COLOURS[i % BLOC_COLOURS.size()])
			seat += 1
	var majority := float(_bar.get_meta("majority", total / 2.0))
	var x := ceilf((majority - 1.0) / SEAT_ROWS) * cell
	var bottom := SEAT_ROWS * cell
	_bar.draw_line(Vector2(x, -2.0), Vector2(x, bottom + 6.0), Palette.INK, 2.0)
	var font := Palette.display(600, 1)
	_bar.draw_string(font, Vector2(x + 6.0, bottom + 20.0), "MAJORITY: %d" % int(majority), HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPS, Palette.INK)

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
