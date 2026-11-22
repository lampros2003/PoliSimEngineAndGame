extends PanelContainer
## "Why did this change?" Shows what moved a figure last month, input by input, and lets
## the player follow any input to its own causes.

const Palette := preload("res://scripts/palette.gd")
const Bar := preload("res://scripts/bar.gd")

signal follow(name: String)
signal back
signal chart(row: String)

var fmt: RefCounted
var entries := {}  # name -> catalogue entry
var trail: PackedStringArray = []

var _title: Label
var _crumbs: Label
var _summary: Label
var _rows: VBoxContainer
var _note: Label
var _back: Button


## Built at once (stage S13.2), so a popup can fill it before it is on screen.
func _init() -> void:
	# Stage S13.2: inside an indicator's popup, which carries the title and Back.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.text = "Why did it change?"
	_title.theme_type_variation = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_back = Button.new()
	_back.text = "Back"
	_back.theme_type_variation = "Link"
	_back.disabled = true
	_back.pressed.connect(func() -> void: back.emit())
	head.add_child(_back)
	head.visible = false
	_crumbs = Label.new()
	_crumbs.add_theme_color_override("font_color", Palette.MUTED)
	_crumbs.add_theme_font_size_override("font_size", Palette.SMALL)
	_crumbs.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_crumbs.visible = false
	box.add_child(_crumbs)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.text = ""
	box.add_child(_summary)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Palette.MUTED)
	_note.add_theme_font_size_override("font_size", Palette.SMALL)
	box.add_child(_note)


func label_of(name: String) -> String:
	return str(entries.get(name, {}).get("label", name))


## Stage S10.5: for `x__k`, a state a lag `x` makes, what the lag follows and `k`: the
## state holds that value as it was k months back. Empty for anything else.
func lag_part(symbol: String) -> Array:
	var lag := str(entries.get(symbol, {}).get("lag", ""))
	if lag == "" or not symbol.begins_with(lag + "__"):
		return []
	var follows: PackedStringArray = entries.get(lag, {}).get("lagged_inputs", PackedStringArray())
	if follows.is_empty():
		return []
	return [follows[0], int(symbol.substr(lag.length() + 2))]


func show_waiting(name: String) -> void:
	_title.text = label_of(name)
	_summary.text = "Working it out…"


func show_error(name: String, message: String) -> void:
	_title.text = label_of(name)
	_clear()
	if message.contains("not enough history"):
		_summary.text = "Advance at least two months to see why figures change."
	else:
		_summary.text = message
	_note.text = ""


func _clear() -> void:
	for child in _rows.get_children():
		child.queue_free()


func show_explanation(e: Dictionary) -> void:
	var name: String = e["name"]
	var entry: Dictionary = entries.get(name, {})
	_back.disabled = trail.size() <= 1
	_crumbs.text = " › ".join(Array(trail).map(func(n): return label_of(n))) if trail.size() > 1 else ""
	_crumbs.visible = _crumbs.text != ""
	_title.text = label_of(name)
	var month: String = fmt.month_name(int(e["step"]))
	var total_note := ""
	if str(e.get("entity", "")) != "":
		total_note = " (all %ss together)" % e["entity"]
	_summary.text = "%s%s: %s, from %s the month before (%s)." % [
		month, total_note, fmt.value(entry, e["now"]), fmt.value(entry, e["before"], true, false), fmt.change(entry, e["change"])]
	_clear()
	var biggest := 0.0
	for part in e["parts"]:
		if part["effect"] != null:
			biggest = maxf(biggest, absf(float(part["effect"])))
	if e["remainder"] != null:
		biggest = maxf(biggest, absf(float(e["remainder"])))
	var shown := 0
	var unchanged := PackedStringArray()
	for part in e["parts"]:
		var effect: Variant = part["effect"]
		var symbol: String = part["symbol"]
		if effect != null and float(effect) == 0.0:
			unchanged.append(part["label"] if symbol == "" else label_of(symbol))
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_button := Button.new()
		name_button.text = part["label"] if symbol == "" else label_of(symbol) + (" (last month)" if part["lagged"] else "")
		# A lag's state is shown, and followed, as the value it holds from months back.
		var lagged := lag_part(symbol)
		if not lagged.is_empty():
			var months: int = lagged[1] + (1 if part["lagged"] else 0)
			name_button.text = "%s (%d month%s before)" % [label_of(lagged[0]), months, "" if months == 1 else "s"]
			symbol = lagged[0]
		name_button.theme_type_variation = "ReportLine"  # stage S13.6: tinted under the pointer
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Stage S14.5: a long name wraps onto a second line, never cut.
		name_button.custom_minimum_size = Vector2(230, 0)
		name_button.size_flags_horizontal = Control.SIZE_FILL
		name_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var input_entry: Dictionary = entries.get(symbol, {})
		var followable := symbol != "" and str(input_entry.get("kind", "")) in ["var", "flow", "state", "account"]
		name_button.disabled = not followable
		if symbol != "":
			name_button.tooltip_text = "%s\nnow %s, before %s" % [str(input_entry.get("doc", "")), fmt.value(input_entry, part["now"]), fmt.value(input_entry, part["before"])]
		if followable:
			name_button.pressed.connect(func() -> void: follow.emit(symbol))
		row.add_child(name_button)
		var bar := Bar.new()
		bar.custom_minimum_size = Vector2(100, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.fraction = 0.0 if effect == null or biggest == 0.0 else float(effect) / biggest
		row.add_child(bar)
		var amount := Label.new()
		amount.custom_minimum_size = Vector2(110, 0)
		amount.clip_text = true
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.text = "not separable" if effect == null else fmt.change(entry, effect)
		row.add_child(amount)
		if symbol != "" and str(input_entry.get("row", "")) != "":
			var plot := Button.new()
			plot.text = "Compare"
			plot.theme_type_variation = "Link"
			var input_row: String = input_entry["row"]
			plot.pressed.connect(func() -> void: chart.emit(input_row))
			row.add_child(plot)
		_rows.add_child(row)
		shown += 1
	if not unchanged.is_empty():
		var quiet := Label.new()
		quiet.text = "Unchanged last month: " + ", ".join(unchanged)
		quiet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quiet.add_theme_color_override("font_color", Palette.MUTED)
		quiet.add_theme_font_size_override("font_size", Palette.SMALL)
		_rows.add_child(quiet)
	var notes := PackedStringArray()
	if str(e.get("note", "")) != "":
		notes.append("This is %s." % e["note"])
	if shown > 0 or not unchanged.is_empty():
		if e["exact"]:
			notes.append("These parts add up exactly to the change.")
		else:
			notes.append("Not explained by any single input on its own (inputs acting together): %s." % fmt.change(entry, e["remainder"]))
		notes.append("Each part is how far that input's own change moved the figure, everything else as it was this month.")
	_note.text = "\n".join(notes)
