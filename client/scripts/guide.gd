extends Control
## Stage S13.6: the first minutes. A few short steps, each a small card with an arrow to a
## real thing on the screen (the centre, a policy, the indicators, the people, Next month),
## the rest of the screen dimmed a little, and Next and Skip. Esc skips; Enter or Space
## goes on. Shown on a player's first game (main.gd decides), and again from the menu.

const Palette := preload("res://scripts/palette.gd")
const Focus := preload("res://scripts/focus.gd")

signal finished

## Each step: {title, text, target: Callable returning a Rect2 on screen}.
var steps: Array = []
var index := 0
## False to leave the "guide seen" setting alone when it ends (the checks).
var remember := true
var card: PanelContainer
var _title: Label
var _text: Label
var _count: Label
var _next: Button
var _skip: Button
var _target := Rect2()


func _ready() -> void:
	name = "guide"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.card(24, 6, 2))
	card.custom_minimum_size.x = 380.0
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	_count = Palette.caps("")
	box.add_child(_count)
	_title = Label.new()
	_title.theme_type_variation = "Title"
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 340.0
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_next = Button.new()
	_next.name = "next"
	_next.theme_type_variation = "Primary"
	_next.pressed.connect(next)
	buttons.add_child(_next)
	_skip = Button.new()
	_skip.name = "skip"
	_skip.text = "Skip the guide"
	_skip.theme_type_variation = "Link"
	_skip.pressed.connect(finish)
	buttons.add_child(_skip)
	resized.connect(_show_step)


func begin(the_steps: Array) -> void:
	steps = the_steps
	index = 0
	visible = not steps.is_empty()
	_show_step()


func next() -> void:
	index += 1
	if index >= steps.size():
		finish()
	else:
		_show_step()


func finish() -> void:
	if not visible:
		return
	visible = false
	finished.emit()


## The step on screen, as its title, and the rectangle it points at.
func step_title() -> String:
	return _title.text if visible else ""


func target() -> Rect2:
	return _target


func _show_step() -> void:
	if not visible or index >= steps.size():
		return
	var step: Dictionary = steps[index]
	_count.text = ("Step %d of %d" % [index + 1, steps.size()]).to_upper()
	_title.text = str(step["title"])
	_text.text = str(step["text"])
	_next.text = "Next" if index < steps.size() - 1 else "Start playing"
	_target = (step["target"] as Callable).call().grow(8.0)
	card.reset_size()
	var box := card.get_combined_minimum_size()
	var view := size
	# The card on the side of its target with the most room, a little way off it.
	var gap := 56.0
	var room := {"right": view.x - _target.end.x, "left": _target.position.x, "below": view.y - _target.end.y, "above": _target.position.y}
	var side := "right"
	for s in room:
		if room[s] - (box.x if s in ["right", "left"] else box.y) > room[side] - (box.x if side in ["right", "left"] else box.y):
			side = s
	var at := Vector2.ZERO
	match side:
		"right":
			at = Vector2(_target.end.x + gap, _target.get_center().y - box.y / 2.0)
		"left":
			at = Vector2(_target.position.x - gap - box.x, _target.get_center().y - box.y / 2.0)
		"below":
			at = Vector2(_target.get_center().x - box.x / 2.0, _target.end.y + gap)
		"above":
			at = Vector2(_target.get_center().x - box.x / 2.0, _target.position.y - gap - box.y)
	card.position = at.clamp(Vector2(12, 12), (view - box - Vector2(12, 12)).max(Vector2(12, 12)))
	card.size = box
	queue_redraw()
	if is_inside_tree():
		_next.grab_focus.call_deferred()


func _draw() -> void:
	var dim := Color(Palette.INK, 0.28)
	var t := _target
	draw_rect(Rect2(0, 0, size.x, t.position.y), dim)
	draw_rect(Rect2(0, t.end.y, size.x, size.y - t.end.y), dim)
	draw_rect(Rect2(0, t.position.y, t.position.x, t.size.y), dim)
	draw_rect(Rect2(t.end.x, t.position.y, size.x - t.end.x, t.size.y), dim)
	draw_rect(t, Palette.OCHRE, false, 3.0)
	draw_rect(t.grow(2.5), Palette.INK, false, 1.0)  # stage S17.1: ochre alone is lost on the dimmed board
	# The arrow from the card to its target.
	var c := Rect2(card.position, card.size)
	var a := Vector2(clampf(t.get_center().x, c.position.x, c.end.x), clampf(t.get_center().y, c.position.y, c.end.y))
	var b := Vector2(clampf(c.get_center().x, t.position.x, t.end.x), clampf(c.get_center().y, t.position.y, t.end.y))
	if a.distance_to(b) > 12.0:
		var dir := (b - a).normalized()
		b -= dir * 4.0
		draw_line(a, b - dir * 10.0, Palette.INK, 3.0, true)
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([b, b - dir * 16.0 + side * 8.0, b - dir * 16.0 - side * 8.0]), Palette.INK)


func _gui_input(event: InputEvent) -> void:
	accept_event()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		finish()
		get_viewport().set_input_as_handled()
	elif visible:
		Focus.kept_inside(card, event)  # stage S17.1: Tab stays on the guide's own buttons
