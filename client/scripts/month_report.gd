extends PanelContainer
## Stage S13.6: the month's report. After "Next month" (or three months, or a year) a
## compact card slides in at the right, under the top bar: the bills that passed, failed or
## were refused; the few figures that moved most against their own usual movement, with
## direction in good or bad colour; any situation that began or ended. Each line opens its
## node's popup. It is not modal: it goes by itself after a while (not while the pointer is
## on it), or on a click, and the date on the top bar brings it back.

const Palette := preload("res://scripts/palette.gd")

## A line was pressed: a board key ("policy:...", "indicator:...", "group:...") or
## "entry:<name>" for a value off the board.
signal line_pressed(key: String)

const WIDTH := 380.0
const STAYS := 9.0  # seconds on screen

## For the checks: the lines shown, as text.
var lines_shown: PackedStringArray = []
var title := ""
var _sections: Array = []  # [heading, [{text, tone, key}]]
var _box: VBoxContainer
var _tween: Tween
var _timer: Timer
var top_margin := 0.0


func _ready() -> void:
	name = "month_report"
	visible = false
	add_theme_stylebox_override("panel", Palette.card(16, 6, 2))
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(func() -> void:
		if get_global_rect().has_point(get_global_mouse_position()):
			_timer.start(2.0)
		else:
			dismiss())
	add_child(_timer)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			dismiss())
	get_viewport().size_changed.connect(_place)


## Fills the report: `sections` is [[heading, [{text, tone ("good", "bad", "plain",
## "notice"), key}]]], empty sections left out. Then slides it in.
func show_report(heading: String, sections: Array) -> void:
	title = heading
	_sections = sections
	_build()
	reopen()


func has_report() -> bool:
	return title != ""


## Slides the last report in again.
func reopen() -> void:
	if title == "":
		return
	visible = true
	reset_size()
	_place()
	var x := position.x
	position.x = get_viewport_rect().size.x + 8.0
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:x", x, 0.28)
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_timer.start(STAYS)


func dismiss() -> void:
	if not visible:
		return
	_timer.stop()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "position:x", get_viewport_rect().size.x + 8.0, 0.18)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.chain().tween_callback(func() -> void: visible = false)


func _place() -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	position = Vector2(view.x - size.x - 16.0, top_margin + 14.0)


func _build() -> void:
	for child in _box.get_children():
		child.queue_free()
	lines_shown.clear()
	var head := Label.new()
	head.text = title
	head.theme_type_variation = "Title"
	head.add_theme_font_size_override("font_size", 22)
	_box.add_child(head)
	var any := false
	for section in _sections:
		var items: Array = section[1]
		if items.is_empty():
			continue
		any = true
		_box.add_child(Palette.caps(str(section[0])))
		for item in items:
			_box.add_child(_line(item))
			lines_shown.append(str(item["text"]))
	if not any:
		var quiet := Label.new()
		quiet.text = "A quiet month: nothing moved out of the ordinary."
		quiet.theme_type_variation = "Muted"
		_box.add_child(quiet)
	var hint := Label.new()
	hint.text = "Click a line to open it; the date on the top bar shows this again."
	hint.theme_type_variation = "Muted"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 40.0
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
	for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, colour)
	var key := str(item.get("key", ""))
	button.disabled = key == ""
	button.pressed.connect(func() -> void:
		dismiss()
		line_pressed.emit(key))
	return button
