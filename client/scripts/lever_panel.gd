extends VBoxContainer
## Stage S13.2: a policy's popup. Its name, pictogram, area and what it is; one control per
## lever (a slider and an exact field, in the units the screen shows: rates in percent,
## large amounts in millions or billions, flows at the rate amounts are shown), the setting
## now and the change waiting (with Undo), what a change costs in political capital and the
## Commons vote it would get; what the waiting change would do in a year; and the lever's
## history with the player's changes marked.
##
## Stage S13.4: the controls come first, with "In a year" beside them when the window is
## wide (under them when not); the year's bars are sage or brick where the scenario says
## which way is better, and the groups most affected follow the indicators. Fields read as
## people write numbers: £12,570, 21%, 21.5%, £12.38bn.

const Palette := preload("res://scripts/palette.gd")
const Chart := preload("res://scripts/chart.gd")
const Bar := preload("res://scripts/bar.gd")
const Format := preload("res://scripts/format.gd")
const Sound := preload("res://scripts/sound.gd")

signal lever_changed(name: String, raw: String)
signal lever_cancelled(name: String)
## The player asked for an indicator's or a group's popup (from the year-ahead table).
signal follow(name: String)

## The popup's width with two columns, and the window width from which it has them.
const WIDE := 1120.0
const WIDE_FROM := 1360.0  # stage S13.6: from 1366x768 up

var fmt: RefCounted
var key := ""  # the board's policy key
var levers: PackedStringArray = []
## True for two columns (set before build).
var wide := false
var hint: Label
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
var _controls: VBoxContainer
var _body: BoxContainer
var _left_scroll: ScrollContainer
var _left_box: VBoxContainer
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
		var places := 0
		for d in [0, 1, 2, 3]:
			places = d
			if is_equal_approx(snappedf(value, pow(10.0, -d)), value):
				break
		text = prefix + Format.grouped(value, places) + suffix

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]:
			apply(value + (arrow_step if event.keycode == KEY_UP else -arrow_step))
			accept_event()


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


## The popup's width for this content.
func popup_width() -> float:
	return WIDE if wide else 640.0


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
	# The controls, and beside them (or under them) what the change would do in a year.
	var body: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	body.add_theme_constant_override("separation", 36 if wide else 12)
	add_child(body)
	_body = body
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 12)
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls.custom_minimum_size.x = 470.0 if wide else 0.0
	# Stage S13.6: two columns, the controls (and the history under them) scrolling on their
	# own when there are many, so "In a year" beside them never scrolls out of sight.
	var column: Control = _controls
	if wide:
		_left_scroll = ScrollContainer.new()
		_left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_left_scroll.custom_minimum_size.x = 490.0
		_left_box = VBoxContainer.new()
		_left_box.add_theme_constant_override("separation", 12)
		_left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_left_scroll.add_child(_left_box)
		_left_box.add_child(_controls)
		_controls.custom_minimum_size.x = 470.0
		column = _left_scroll
	body.add_child(column)
	for entry in entries:
		_lever_row(entry, start_of.call(str(entry["name"])))
		levers.append(str(entry["name"]))
	hint = _muted("Changes are bills: the Commons votes on them next month." if legislature else "Changes take effect from next month.")
	_controls.add_child(hint)
	capital_note = _muted("")
	capital_note.name = "capital_note"
	capital_note.visible = false
	_controls.add_child(capital_note)
	_year = VBoxContainer.new()
	_year.add_theme_constant_override("separation", 6)
	_year.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_year.custom_minimum_size.x = 500.0 if wide else 0.0
	body.add_child(_year)
	_year_title = Palette.caps("In a year")
	_year.add_child(_year_title)
	_year_note = _muted("Move a control to see what the change would do in a year.")
	_year_note.custom_minimum_size.x = 0.0
	_year.add_child(_year_note)
	_year_rows = _table()
	_year.add_child(_year_rows)
	_group_title = Palette.caps("The groups it moves most")
	_group_title.visible = false
	_year.add_child(_group_title)
	_group_rows = _table()
	_year.add_child(_group_rows)
	_year.visible = wide
	_chart_lever = levers[0] if not levers.is_empty() else ""
	var holder: Control = _left_box if wide else self
	holder.add_child(Palette.caps("History" if levers.size() == 1 else "History: " + str(_rows[_chart_lever]["entry"].get("label", _chart_lever))))
	chart = Chart.new()
	chart.fmt = fmt
	chart.custom_minimum_size = Vector2(0, 190)
	holder.add_child(chart)


## Stage S13.6: in two columns, the controls' column takes the room the popup has (`room`,
## its scrolling height), so a policy of many levers scrolls its controls, not the popup.
func fit_height(room: float) -> void:
	if _left_scroll == null:
		return
	var inner := _left_box.get_combined_minimum_size().y
	var fixed := get_combined_minimum_size().y - _body.get_combined_minimum_size().y
	_left_scroll.custom_minimum_size.y = clampf(room - fixed - 6.0, minf(260.0, inner), inner)


func _table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
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
	slider.custom_minimum_size = Vector2(200, 24)
	controls.add_child(slider)
	var spin := Field.new()
	spin.custom_minimum_size = Vector2(150, 0)
	spin.name = "lever_" + name
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var scale := _scale(entry)
	var rate: bool = fmt.is_rate(entry)
	var money: bool = entry.get("money", false)
	if entry.get("has_range", false):
		spin.min_value = float(entry["min"]) * scale
		spin.max_value = float(entry["max"]) * scale
	if rate:
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
	_controls.add_child(box)
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
		var spin: Field = row["spin"]
		var shown: Variant = pending.get(name, value)
		if shown != null and not spin.has_focus():
			spin.apply(float(shown) * _scale(entry), false)
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
		capital_note.text = ("Political capital: %.1f to spend; a bill costs more the further it moves a policy." % capital
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
## {row: [as is, without the change]}, `shown` the [row key, label, entry, kind, tier,
## better] that may be listed: the first always, then the three budget lines (kind
## "budget") and the six other rows that move most; and, under them, the five groups
## (kind "group") whose approval moves most.
func show_year(rows: Dictionary, shown: Array, working := false) -> void:
	_year.visible = true
	_year_note.visible = false
	for grid in [_year_rows, _group_rows]:
		for child in grid.get_children():
			child.queue_free()
	_group_title.visible = false
	if working:
		_year_title.text = "IN A YEAR: WORKING IT OUT…"
		return
	_year_title.text = "IN A YEAR, WITH THE CHANGE"
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
		_year.visible = wide
		_year_note.visible = wide
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
		name.theme_type_variation = "Link"
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.custom_minimum_size = Vector2(170, 0)
		var target := str(item[6]) if item.size() > 6 else str(item[2].get("name", ""))
		name.pressed.connect(func() -> void: follow.emit(target))
		grid.add_child(name)
		var bar := Bar.new()
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.fraction = ((absf(it[1]) if groups else it[3]) / biggest) * signf(it[1])
		# Sage for a change for the better, brick for the worse, where that is known.
		var better := str(item[5]) if item.size() > 5 else ""
		bar.up_colour = Palette.INK if better == "" else (Palette.SAGE if better == "high" else Palette.BRICK)
		bar.down_colour = Palette.INK if better == "" else (Palette.BRICK if better == "high" else Palette.SAGE)
		grid.add_child(bar)
		var amount := Label.new()
		amount.text = fmt.change(item[2], it[1])
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.custom_minimum_size = Vector2(110, 0)
		grid.add_child(amount)


func hide_year() -> void:
	_year.visible = wide
	_year_note.visible = wide
	for grid in [_year_rows, _group_rows]:
		for child in grid.get_children():
			child.queue_free()
	_group_title.visible = false
	_year_title.text = "IN A YEAR"


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
	var spin: Field = _rows[name]["spin"]
	if fmt.is_rate(entry):
		spin.apply(value)
	elif entry.get("money", false):
		spin.apply(value * float(fmt.minor) * _scale(entry))
	else:
		spin.apply(value * _scale(entry))


## For tests: what a lever's field reads.
func field_text(name: String) -> String:
	return str(_rows[name]["spin"].text) if _rows.has(name) else ""


func pending_text(name: String) -> String:
	return str(_rows[name]["pending"].text) if _rows.has(name) else ""
