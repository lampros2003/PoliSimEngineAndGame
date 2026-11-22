extends Control
## Stage S14.1: the strip under the top bar, always there so it never moves the board. At
## its left, under the date, one line: a notice or an ordinary month's news, gone after a few
## seconds (a problem stays until clicked; a click on a longer one opens the whole of it).
## At its right, the situations in force and the questions and answers as pennants: green if
## good, red if bad, blue if neither, ochre for a question waiting. Pointing at one says since
## when; a click opens it.

const Palette := preload("res://scripts/palette.gd")

signal flag_pressed(flag: Dictionary)
## The line was clicked while it holds more than it shows.
signal line_pressed(full: String)

const HEIGHT := 34.0

## The flags shown: each {key, text, since, tone ("good", "bad", "plain", "ask"), doc, ...}.
var flags: Array = []
## For the checks: the whole of the notice on the line, or "" when none is shown.
var line_text := ""
var _line: Label
var _row: HBoxContainer
var _timer: Timer
var _full := ""


func _ready() -> void:
	name = "strip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = Label.new()
	_line.name = "line"
	_line.add_theme_font_override("font", Palette.text(500))
	_line.add_theme_font_size_override("font_size", 15)
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.clip_text = true
	_line.mouse_filter = Control.MOUSE_FILTER_STOP
	_line.visible = false
	_line.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var full := _full
			hide_line()
			if full.contains("\n"):
				line_pressed.emit(full))
	add_child(_line)
	_row = HBoxContainer.new()
	_row.name = "flags"
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_line)
	add_child(_timer)
	resized.connect(_arrange)


## Shows `text` (bbcode allowed; its first line is what shows) on the line. `stay` seconds,
## or until clicked when 0. A problem is in red.
func show_line(text: String, problem := false, stay := 4.0) -> void:
	var plain := _plain(text)
	_full = plain
	line_text = plain
	_line.text = plain.get_slice("\n", 0) + ("  ›" if plain.contains("\n") else ("   ✕" if problem and stay <= 0.0 else ""))
	_line.tooltip_text = plain if plain.contains("\n") else ("Click to dismiss" if problem and stay <= 0.0 else "")
	_line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_line.add_theme_color_override("font_color", Palette.BAD if problem else Palette.INK)
	_line.add_theme_font_override("font", Palette.text(600 if problem else 500))
	_line.visible = true
	_arrange()
	if stay > 0.0:
		_timer.start(stay)
	else:
		_timer.stop()
	# Faded in, never slid: nothing on the screen moves for it.
	_line.modulate.a = 0.0
	create_tween().tween_property(_line, "modulate:a", 1.0, 0.12)


func hide_line() -> void:
	_timer.stop()
	_line.visible = false
	line_text = ""
	_full = ""


func line_visible() -> bool:
	return _line.visible


## The flags in force; rebuilt only when they change.
func set_flags(list: Array) -> void:
	if list == flags:
		return
	flags = list
	for child in _row.get_children():
		child.queue_free()
	for f in list:
		var pennant := Pennant.new()
		pennant.flag = f
		pennant.name = "flag_" + str(f["key"])
		pennant.tooltip_text = str(f["text"]) + str(f.get("since", "")) + ("\n" + str(f["doc"]) if str(f.get("doc", "")) != "" else "")
		var which: Dictionary = f
		pennant.pressed.connect(func() -> void: flag_pressed.emit(which))
		_row.add_child(pennant)
	_arrange.call_deferred()


## A flag's words and since when, or "".
func flag_text(key: String) -> String:
	for f in flags:
		if str(f["key"]) == key:
			return str(f["text"]) + str(f.get("since", ""))
	return ""


func _arrange() -> void:
	var wide := _row.get_combined_minimum_size().x
	_row.position = Vector2(size.x - 16.0 - wide, 4.0)
	_row.size = Vector2(wide, size.y - 8.0)
	_line.position = Vector2(18.0, 0.0)
	_line.size = Vector2(maxf(size.x - wide - 60.0, 100.0), size.y)


static func _plain(bbcode: String) -> String:
	var out := RegEx.create_from_string("\\[/?[a-z_=#0-9 ]+\\]").sub(bbcode, "", true)
	return out.strip_edges()


## A pennant: a staff on the left, the cloth notched on the right, in the tone's ink.
class Pennant extends Control:
	signal pressed
	var flag := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var font := Palette.text(600 if flag.get("tone", "") == "ask" else 500)
		custom_minimum_size = Vector2(font.get_string_size(str(flag["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 34.0, 26.0)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()

	static func colour_of(tone: String) -> Color:
		return {"good": Palette.BETTER, "bad": Palette.WORSE, "ask": Palette.ASK}.get(tone, Palette.STEADY)

	func _draw() -> void:
		var tone := str(flag.get("tone", "plain"))
		var rect := Rect2(Vector2(0, 1), size - Vector2(3, 4))
		var notch := rect.size.y * 0.3
		var cloth := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - notch, rect.get_center().y),
			Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)])
		var shadow := PackedVector2Array()
		for p in cloth:
			shadow.append(p + Vector2(3, 3))
		draw_colored_polygon(shadow, Palette.SHADOW)
		draw_colored_polygon(cloth, colour_of(tone))
		cloth.append(cloth[0])
		var hot := get_global_rect().has_point(get_global_mouse_position())
		draw_polyline(cloth, Palette.INK, 3.0 if hot else 1.5, true)
		var font := Palette.text(600 if tone == "ask" else 500)
		draw_string(font, Vector2(10, rect.get_center().y + 14 * 0.36), str(flag["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Palette.INK if tone == "ask" else Palette.CARD)
