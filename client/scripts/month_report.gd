extends PanelContainer
## Stage S13.6: the month's report: the bills that passed, failed or were refused; the few
## figures that moved most against their own usual movement, with direction in good or bad
## colour; any situation that began or ended. Each line opens its node's popup.
##
## Stage S14.1: a window over the board, never beside it: the board keeps its size. It opens
## by itself only when the months played have something to tell (main.gd decides), from the
## date on the top bar, which also opens it again. It stays until closed (Close, Esc, a line
## clicked, the next month), and takes no room from anything.

const Palette := preload("res://scripts/palette.gd")

## A line was pressed: a board key ("policy:...", "indicator:...", "group:...") or
## "entry:<name>" for a value off the board.
signal line_pressed(key: String)

const WIDTH := 460.0

## For the checks: the lines shown, as text.
var lines_shown: PackedStringArray = []
var title := ""
## Where it stands: below the top bar and the strip, under the date.
var top_margin := 0.0
var _sections: Array = []  # [heading, [{text, tone, key}], note]
var _box: VBoxContainer
var _head: Label
var _tween: Tween


func _ready() -> void:
	name = "month_report"
	visible = false
	add_theme_stylebox_override("panel", Palette.card(0, 6, 2))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var bar_margin := MarginContainer.new()
	for side in ["left", "right"]:
		bar_margin.add_theme_constant_override("margin_" + side, 20)
	bar_margin.add_theme_constant_override("margin_top", 14)
	column.add_child(bar_margin)
	var bar := HBoxContainer.new()
	bar_margin.add_child(bar)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(titles)
	titles.add_child(Palette.caps("The month's report"))
	_head = Label.new()
	_head.theme_type_variation = "Title"
	_head.add_theme_font_size_override("font_size", 24)
	titles.add_child(_head)
	var close := Button.new()
	close.name = "close"
	close.text = "Close  ✕"
	close.theme_type_variation = "Link"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(dismiss)
	bar.add_child(close)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 18)
	column.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.custom_minimum_size.x = WIDTH - 40.0
	margin.add_child(_box)
	get_viewport().size_changed.connect(_place)


## Fills the report: `sections` is [[heading, [{text, tone ("good", "bad", "plain",
## "notice"), key}], note]], empty sections left out. It is not shown until reopen().
func set_report(heading: String, sections: Array) -> void:
	title = heading
	_sections = sections
	_build()


## Fills the report and opens it.
func show_report(heading: String, sections: Array) -> void:
	set_report(heading, sections)
	reopen()


func has_report() -> bool:
	return title != ""


## Opens the last report again, growing from the date at the top left.
func reopen() -> void:
	if title == "":
		return
	visible = true
	reset_size()
	_place()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot_offset = Vector2.ZERO
	scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	_tween.tween_property(self, "modulate:a", 1.0, 0.1)


func dismiss() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	scale = Vector2.ONE
	modulate.a = 1.0


func _place() -> void:
	if not visible:
		return
	position = Vector2(16.0, top_margin + 10.0)


func _build() -> void:
	for child in _box.get_children():
		child.queue_free()
	lines_shown.clear()
	_head.text = title
	var any := false
	for section in _sections:
		var items: Array = section[1]
		if items.is_empty():
			continue
		any = true
		var caps := Palette.caps(str(section[0]))
		if _box.get_child_count() > 0:
			caps.custom_minimum_size.y = 30.0
			caps.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_box.add_child(caps)
		for item in items:
			_box.add_child(_line(item))
			lines_shown.append(str(item["text"]))
		if section.size() > 2 and str(section[2]) != "":
			var note := Label.new()
			note.text = str(section[2])
			note.theme_type_variation = "Muted"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = WIDTH - 40.0
			_box.add_child(note)
	if not any:
		var quiet := Label.new()
		quiet.text = "A quiet month: nothing moved out of the ordinary."
		quiet.theme_type_variation = "Muted"
		_box.add_child(quiet)
	var hint := Label.new()
	hint.text = "Click a line to open it; click the date to see this again."
	hint.theme_type_variation = "Muted"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WIDTH - 40.0, 34.0)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_box.add_child(hint)


func _line(item: Dictionary) -> Button:
	var button := Button.new()
	button.theme_type_variation = "ReportLine"
	button.text = str(item["text"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.x = WIDTH - 40.0
	var tone := str(item.get("tone", "plain"))
	var colour: Color = {"good": Palette.GOOD, "bad": Palette.BAD, "notice": Palette.BAD}.get(tone, Palette.INK)
	for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(key, colour)
	var key := str(item.get("key", ""))
	button.disabled = key == ""
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if key != "" else Control.CURSOR_ARROW
	button.pressed.connect(func() -> void:
		dismiss()
		line_pressed.emit(key))
	return button
