extends VBoxContainer
## Stage S13.2: a policy's popup. Its name, pictogram, area and what it is; one control per
## lever (a slider and an exact field, in the units the screen shows: rates in percent,
## large amounts in millions or billions, flows at the rate amounts are shown), the setting
## now and the change waiting (with Undo), what a change costs in political capital and the
## Commons vote it would get; what the waiting change would do in a year; and the lever's
## history with the player's changes marked.

const Palette := preload("res://scripts/palette.gd")
const Chart := preload("res://scripts/chart.gd")
const Bar := preload("res://scripts/bar.gd")

signal lever_changed(name: String, raw: String)
signal lever_cancelled(name: String)
## The player asked for an indicator's popup (from the year-ahead table).
signal follow(name: String)

var fmt: RefCounted
var key := ""  # the board's policy key
var levers: PackedStringArray = []
var hint: Label
var capital_note: Label
var chart: Chart
var _rows := {}  # name -> {entry, spin, slider, now, pending, cancel, vote}
var _units := {}  # name -> amount one unit of a money input stands for: 1, 1e6 or 1e9
var _dragging := ""
var _chart_lever := ""
## The year-ahead table as shown: [label, change] per row, for tests.
var year_shown: Array = []
var _year: VBoxContainer
var _year_title: Label
var _year_rows: GridContainer


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


## `node` is the board's policy node; `entries` the levers' catalogue entries in order;
## `start_of(name)` where a lever began (the slider spans up to twice that for a lever
## whose range is far wider than play).
func build(node: Dictionary, entries: Array, legislature: bool, start_of: Callable) -> void:
	key = str(node.get("key", ""))
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var badge := TextureRect.new()
	badge.texture = node.get("icon")
	badge.custom_minimum_size = Vector2(56, 56)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = Palette.INK
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(Palette.caps(str(node.get("area", "Policy"))))
	var title := Label.new()
	title.text = str(node.get("label", ""))
	title.theme_type_variation = "Title"
	titles.add_child(title)
	if entries.size() == 1 and str(entries[0].get("doc", "")) != "":
		add_child(_muted(_sentence(str(entries[0]["doc"]))))
	hint = _muted("Changes are bills: the House of Commons votes on them at the start of next month, and a government without a majority of its own can lose them."
		if legislature else "Changes take effect from next month.")
	add_child(hint)
	capital_note = _muted("")
	capital_note.name = "capital_note"
	capital_note.visible = false
	add_child(capital_note)
	# What the waiting change would do in a year (stage S13.3 joins it to the bridge).
	_year = VBoxContainer.new()
	_year.add_theme_constant_override("separation", 6)
	_year.visible = false
	add_child(_year)
	_year_title = Palette.caps("In a year")
	_year.add_child(_year_title)
	_year_rows = GridContainer.new()
	_year_rows.columns = 3
	_year_rows.add_theme_constant_override("h_separation", 12)
	_year_rows.add_theme_constant_override("v_separation", 6)
	_year.add_child(_year_rows)
	for entry in entries:
		_lever_row(entry, start_of.call(str(entry["name"])))
		levers.append(str(entry["name"]))
	_chart_lever = levers[0] if not levers.is_empty() else ""
	add_child(Palette.caps("History" if levers.size() == 1 else "History: " + str(_rows[_chart_lever]["entry"].get("label", _chart_lever))))
	chart = Chart.new()
	chart.fmt = fmt
	chart.custom_minimum_size = Vector2(0, 190)
	add_child(chart)


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
	top.add_theme_constant_override("separation", 10)
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
	controls.add_theme_constant_override("separation", 14)
	box.add_child(controls)
	var slider := HSlider.new()
	slider.name = "slider_" + name
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 24)
	controls.add_child(slider)
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
		if _dragging == name:
			spin.set_value_no_signal(value)
		else:
			spin.value = value)
	slider.drag_started.connect(func() -> void: _dragging = name)
	slider.drag_ended.connect(func(changed: bool) -> void:
		_dragging = ""
		if changed:
			spin.value = slider.value)
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
	vote.visible = false
	box.add_child(vote)
	add_child(box)
	_rows[name] = {"entry": entry, "spin": spin, "slider": slider, "now": now, "pending": pending, "cancel": cancel, "vote": vote}


static func _thin_rule() -> StyleBoxLine:
	var rule := StyleBoxLine.new()
	rule.color = Palette.RULE
	rule.thickness = 1
	return rule


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
## `costs`: each waiting change's cost in political capital (stage S12.5); `capital`: what
## there is to spend, or -1 for a model without it.
func refresh(current: Callable, pending: Dictionary, costs := {}, capital := -1.0) -> void:
	for name in _rows:
		var row: Dictionary = _rows[name]
		var entry: Dictionary = row["entry"]
		var value: Variant = current.call(name)
		row["now"].text = ("now " + fmt.value(entry, value, false, false)) if value != null else ""
		var spin: SpinBox = row["spin"]
		var shown: Variant = pending.get(name, value)
		if shown != null and not spin.get_line_edit().has_focus():
			spin.set_value_no_signal(float(shown) * _scale(entry))
		if shown != null and _dragging != name:
			row["slider"].set_value_no_signal(float(shown) * _scale(entry))
		if pending.has(name):
			var cost: float = costs.get(name, -1.0)
			row["pending"].text = "→ %s from next month%s" % [fmt.value(entry, pending[name], false, false),
				"" if cost < 0.0 else " · costs %.1f political capital" % cost]
			row["cancel"].visible = true
		else:
			row["pending"].text = ""
			row["cancel"].visible = false
			row["vote"].visible = false
	capital_note.visible = capital >= 0.0
	if capital >= 0.0:
		var total := 0.0
		for name in costs:
			total += maxf(float(costs[name]), 0.0)
		var short := total > capital
		capital_note.text = ("Political capital: %.1f to spend. Each bill costs some, more the further it moves a policy." % capital
			if costs.is_empty() else "The bills waiting cost %.1f of the %.1f political capital there is.%s" % [total, capital,
			" Not all of them can be put to the Commons: those that cost more than is left when their turn comes are refused." if short else ""])
		capital_note.add_theme_color_override("font_color", Palette.BAD if short else Palette.MUTED)


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

## What the changes waiting would do in a year, as signed bars: `rows` is the forecast's
## {row: [as is, without the change]}, `shown` the [row key, label, entry] that may be listed:
## the first always, then the three budget lines (marked "budget" fourth) and the six other
## rows that move most.
func show_year(rows: Dictionary, shown: Array, working := false) -> void:
	_year.visible = true
	for child in _year_rows.get_children():
		child.queue_free()
	if working:
		_year_title.text = "IN A YEAR: WORKING IT OUT…"
		return
	_year_title.text = "IN A YEAR, WITH THE CHANGE"
	var items := []
	var biggest := 1e-12
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
		_year.visible = false
		return
	# The first row (the budget balance) stays first; the rest, the largest moves.
	var first: Array = items.slice(0, 1)
	var rest: Array = items.slice(1).filter(func(it): return it[2] > 1e-5)
	rest.sort_custom(func(a, b): return a[2] > b[2])
	var board_rows: Array = rest.filter(func(it): return it[0].size() < 4 or it[0][3] != "budget")
	var budget_rows: Array = rest.filter(func(it): return it[0].size() >= 4 and it[0][3] == "budget")
	items = first + budget_rows.slice(0, 3) + board_rows.slice(0, 6)
	year_shown = items.map(func(it): return [str(it[0][1]), float(it[1])])
	for it in items:
		biggest = maxf(biggest, it[3])
	for it in items:
		var item: Array = it[0]
		var name := Button.new()
		name.text = str(item[1])
		name.theme_type_variation = "Link"
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.custom_minimum_size = Vector2(170, 0)
		var target := str(item[2].get("name", ""))
		name.pressed.connect(func() -> void: follow.emit(target))
		_year_rows.add_child(name)
		var bar := Bar.new()
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.fraction = (it[3] / biggest) * signf(it[1])
		bar.up_colour = Palette.BLUE
		bar.down_colour = Palette.BRICK
		_year_rows.add_child(bar)
		var amount := Label.new()
		amount.text = fmt.change(item[2], it[1])
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.custom_minimum_size = Vector2(110, 0)
		_year_rows.add_child(amount)


func hide_year() -> void:
	_year.visible = false


## The first lever's history, with the player's past changes to any of the policy's levers.
func show_history(steps: PackedInt64Array, values: PackedFloat64Array, markers: Array) -> void:
	if _chart_lever == "":
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
	var spin: SpinBox = _rows[name]["spin"]
	if fmt.is_rate(entry):
		spin.value = value
	elif entry.get("money", false):
		spin.value = value * float(fmt.minor) * _scale(entry)
	else:
		spin.value = value * _scale(entry)


func pending_text(name: String) -> String:
	return str(_rows[name]["pending"].text) if _rows.has(name) else ""
