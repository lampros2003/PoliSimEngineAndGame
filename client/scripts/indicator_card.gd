extends VBoxContainer
## Stage S13.2: an indicator's popup (and a budget line's, a top-bar figure's and a
## situation's; stage S13.4 gives interest groups a popup of their own, group_card.gd). The figure large with last month's change;
## its history, with one more series to compare; why it moved (the S6 trace, whose inputs
## open their own popups); its breakdowns where the scenario gives them; and the policies
## that move it most.

const Palette := preload("res://scripts/palette.gd")
const Chart := preload("res://scripts/chart.gd")
const TracePanel := preload("res://scripts/trace_panel.gd")
const BreakdownPanel := preload("res://scripts/breakdown_panel.gd")
const LeverPanel := preload("res://scripts/lever_panel.gd")

## The player followed a cause: an entry's name, or a board key ("policy:...").
signal follow(name: String)

var fmt: RefCounted
var name_shown := ""  # the catalogue entry shown
var row := ""  # its result row, "-" in front when shown negated
var entry := {}
var chart: Chart
var trace: TracePanel
var breakdown: BreakdownPanel
var _figure: Label
var _change: Label
var _compare: OptionButton
var _compare_rows: Array = []  # [row key, label]
var _movers: VBoxContainer


## `node` is the board node shown, or {} for an entry off the board; `label` its label;
## `breakdowns` the breakdown names that belong to it; `compare` [row key, label] of the
## board's indicators in the same unit; `movers` [[policy key, label, signed strength,
## measured]].
func build(name: String, row_key: String, the_entry: Dictionary, label: String, area: String, icon: Texture2D, entries: Dictionary,
		play: Dictionary, breakdowns: Array, compare: Array, movers: Array) -> void:
	name_shown = name
	row = row_key
	_entries = entries
	entry = the_entry
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var badge := TextureRect.new()
	badge.texture = icon
	badge.custom_minimum_size = Vector2(56, 56)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = Palette.INK
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(Palette.caps(area if area != "" else _kind_word()))
	var title := Label.new()
	title.text = label
	title.theme_type_variation = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 14)
	add_child(figures)
	_figure = Label.new()
	_figure.theme_type_variation = "Figure"
	_figure.add_theme_font_size_override("font_size", 44)
	figures.add_child(_figure)
	_change = Label.new()
	_change.size_flags_vertical = Control.SIZE_SHRINK_END
	_change.add_theme_font_override("font", Palette.text(600))
	figures.add_child(_change)
	if str(entry.get("doc", "")) != "":
		add_child(_muted(LeverPanel._sentence(str(entry["doc"]))))
	if row != "":
		var chart_head := HBoxContainer.new()
		chart_head.add_child(Palette.caps("History"))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart_head.add_child(spacer)
		_compare = OptionButton.new()
		_compare.name = "compare"
		_compare.add_item("Compare with…")
		_compare_rows = compare
		for c in compare:
			_compare.add_item(str(c[1]))
		_compare.visible = not compare.is_empty()
		chart_head.add_child(_compare)
		add_child(chart_head)
		chart = Chart.new()
		chart.fmt = fmt
		chart.custom_minimum_size = Vector2(0, 200)
		chart.entry = entry
		chart.series_removed.connect(func(r: String) -> void:
			if r != row and chart.series.size() > 1:
				chart.series.resize(1)
				chart.queue_redraw())
		add_child(chart)
	var why := Palette.caps("Why it moved last month")
	add_child(why)
	trace = TracePanel.new()
	trace.fmt = fmt
	trace.entries = entries
	add_child(trace)
	trace.follow.connect(func(n: String) -> void: follow.emit(n))
	trace.chart.connect(func(r: String) -> void: compare_with(r, str(entries.get(_entry_of_row(entries, r), {}).get("label", r))))
	if not breakdowns.is_empty():
		add_child(Palette.caps("Who gains, who loses"))
		breakdown = BreakdownPanel.new()
		breakdown.fmt = fmt
		add_child(breakdown)
		breakdown.build(play, entries, breakdowns)
	if not movers.is_empty():
		add_child(Palette.caps("What moves it most"))
		_movers = VBoxContainer.new()
		_movers.add_theme_constant_override("separation", 2)
		add_child(_movers)
		for m in movers.slice(0, 6):
			var button := Button.new()
			button.theme_type_variation = "Link"
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var measured: bool = m[3]
			var mark := ""
			if measured:
				mark = ("▲ " if float(m[2]) > 0.0 else "▼ ")
			button.text = mark + str(m[1]) + ("" if measured else "  (through the model's formulas)")
			var target := str(m[0])
			button.pressed.connect(func() -> void: follow.emit(target))
			_movers.add_child(button)
	if _compare != null:
		_compare.item_selected.connect(func(i: int) -> void:
			if i > 0:
				compare_with(str(_compare_rows[i - 1][0]), str(_compare_rows[i - 1][1])))


static func _entry_of_row(entries: Dictionary, r: String) -> String:
	for n in entries:
		if str(entries[n].get("row", "")) == r:
			return n
	return r


func _kind_word() -> String:
	match str(entry.get("kind", "")):
		"flow":
			return "Payment"
		"lever":
			return "Policy"
		"account":
			return "Account"
	return "Indicator"


func _muted(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.theme_type_variation = "Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	return label


## Last month's value and change; `value_of` and `before_of` read result rows.
func refresh(value_of: Callable, before_of: Callable, better: String) -> void:
	if row == "":
		_figure.text = "–"
		return
	var now: Variant = value_of.call(row)
	var was: Variant = before_of.call(row)
	_figure.text = fmt.value(entry, now, true, false)
	_change.text = "no change yet"
	_change.add_theme_color_override("font_color", Palette.MUTED)
	if now != null and was != null and typeof(now) != TYPE_BOOL:
		var d := float(now) - float(was)
		if d != 0.0:
			_change.text = ("▲ " if d > 0.0 else "▼ ") + fmt.change(entry, d) + " on last month"
			if better != "":
				_change.add_theme_color_override("font_color", Palette.GOOD if (d > 0.0) == (better == "high") else Palette.BAD)
			else:
				_change.add_theme_color_override("font_color", Palette.INK)
		else:
			_change.text = "no change on last month"


## The history: this figure, and the one it is compared with.
func show_history(steps: PackedInt64Array, markers: Array, series_of: Callable) -> void:
	if chart == null:
		return
	var k: float = fmt.factor(entry)
	var first := chart.series.is_empty()
	if first:
		chart.series = [{"row": row, "label": str(entry.get("label", row)), "values": PackedFloat64Array(), "color": Palette.BLUE}]
	for s in chart.series:
		var values: PackedFloat64Array = series_of.call(str(s["row"]).trim_prefix("-"))
		var sign := -1.0 if str(s["row"]).begins_with("-") else 1.0
		for i in values.size():
			values[i] *= sign * k
		s["values"] = values
	chart.set_data(steps, markers)
	_series_of = series_of
	_steps = steps
	_markers = markers


var _series_of: Callable
var _steps := PackedInt64Array()
var _markers: Array = []
var _entries := {}


## Adds one more series to the chart, in brick; a second comparison replaces the first.
func compare_with(r: String, label: String) -> void:
	if chart == null or r == row:
		return
	var other: Dictionary = _entries.get(_entry_of_row(_entries, r.trim_prefix("-")), {})
	if [other.get("shown_unit", ""), fmt.is_money(other), fmt.is_rate(other)] != [entry.get("shown_unit", ""), fmt.is_money(entry), fmt.is_rate(entry)]:
		return  # one axis, one unit
	if chart.series.size() > 1:
		chart.series.resize(1)
	chart.series.append({"row": r, "label": label, "values": PackedFloat64Array(), "color": Palette.BRICK})
	if _series_of.is_valid():
		show_history(_steps, _markers, _series_of)
