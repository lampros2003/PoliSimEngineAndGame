extends Control
## Stage S13.2: the one popup. It grows from what was clicked (a node, a figure on the top
## bar, a budget line) with a slight overshoot and closes faster than it opens; the board
## behind it dims. Esc or a click outside closes it. Following a cause inside it replaces
## the content and offers Back.

const Palette := preload("res://scripts/palette.gd")

signal closed

const WIDTH := 640.0
const MARGIN := 16.0

var card: PanelContainer
var content: Control
## What to rebuild for Back: each [Callable returning a Control, origin Rect2].
var stack: Array = []
## Space kept clear at the top of the window (the top bar).
var top_margin := 0.0
var _veil: ColorRect
var _scroll: ScrollContainer
var _holder: MarginContainer
var _back: Button
var _tween: Tween
var _origin := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_veil = ColorRect.new()
	_veil.color = Color(Palette.INK, 0.22)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_veil)
	card = PanelContainer.new()
	card.name = "popup_card"
	card.add_theme_stylebox_override("panel", Palette.card(0, 8, 2))
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var bar := HBoxContainer.new()
	var bar_margin := MarginContainer.new()
	for side in ["left", "right"]:
		bar_margin.add_theme_constant_override("margin_" + side, 14)
	bar_margin.add_theme_constant_override("margin_top", 8)
	bar_margin.add_child(bar)
	column.add_child(bar_margin)
	_back = Button.new()
	_back.name = "back"
	_back.text = "‹ Back"
	_back.theme_type_variation = "Link"
	_back.pressed.connect(back)
	bar.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var close_button := Button.new()
	close_button.name = "close"
	close_button.text = "Close  ✕"
	close_button.theme_type_variation = "Link"
	close_button.pressed.connect(close)
	bar.add_child(close_button)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_holder = MarginContainer.new()
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		_holder.add_theme_constant_override("margin_" + side, 28)
	_holder.add_theme_constant_override("margin_top", 2)
	_holder.add_theme_constant_override("margin_bottom", 26)
	_scroll.add_child(_holder)


func is_open() -> bool:
	return visible and content != null


## Opens on new content (`build` returns it) growing from `origin`, a rectangle on screen.
func open(build: Callable, origin: Rect2) -> void:
	stack.clear()
	_show(build, origin, true)


## Replaces the content, keeping the last for Back.
func push(build: Callable) -> void:
	if not is_open():
		open(build, _origin)
		return
	_show(build, _origin, false)


func back() -> void:
	if stack.size() < 2:
		return
	stack.pop_back()
	var last: Array = stack.pop_back()
	_show(last[0], last[1], false)


func _show(build: Callable, origin: Rect2, grow: bool) -> void:
	if content != null:
		_holder.remove_child(content)
		content.queue_free()
		content = null
	content = build.call()
	content.custom_minimum_size.x = _width() - 56.0
	_holder.add_child(content)
	stack.append([build, origin])
	_origin = origin
	_back.visible = stack.size() > 1
	_scroll.scroll_vertical = 0
	visible = true
	_place.call_deferred(grow)
	# Wrapped text settles its height a frame later: place the card again then.
	get_tree().process_frame.connect(func() -> void:
		if not get_tree().process_frame.is_connected(_place.bind(false)):
			get_tree().process_frame.connect(_place.bind(false), CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)


## Beside what was clicked, on the side with more room, inside the window.
func _place(grow: bool) -> void:
	if content == null:
		return
	var view := get_viewport_rect().size
	var tall := content.get_combined_minimum_size().y + 4.0
	var room := view.y - top_margin - 2.0 * MARGIN - 50.0
	_scroll.custom_minimum_size = Vector2(_width(), minf(tall, room))
	card.reset_size()
	var box := card.get_combined_minimum_size()
	var x := 0.0
	if _origin.get_center().x < view.x / 2.0:
		x = _origin.end.x + 28.0
		if x + box.x > view.x - MARGIN:
			x = view.x - MARGIN - box.x
	else:
		x = _origin.position.x - 28.0 - box.x
		if x < MARGIN:
			x = MARGIN
	var y := clampf(_origin.get_center().y - box.y / 2.0, top_margin + MARGIN, maxf(top_margin + MARGIN, view.y - MARGIN - box.y))
	card.position = Vector2(x, y)
	card.size = box
	if not grow:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	card.pivot_offset = (_origin.get_center() - card.position).clamp(Vector2.ZERO, box)
	card.scale = Vector2(0.18, 0.18)
	card.modulate.a = 0.0
	_veil.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "modulate:a", 1.0, 0.09)
	_tween.tween_property(_veil, "modulate:a", 1.0, 0.18)


## Stage S13.4: the card's width: the content's own (a policy's two columns), or WIDTH.
func _width() -> float:
	if content != null and content.has_method("popup_width"):
		return minf(content.popup_width(), get_viewport_rect().size.x - 2.0 * MARGIN)
	return WIDTH


func close() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var gone := content
	content = null
	stack.clear()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(card, "scale", Vector2(0.7, 0.7), 0.11).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(card, "modulate:a", 0.0, 0.11)
	_tween.tween_property(_veil, "modulate:a", 0.0, 0.11)
	_tween.chain().tween_callback(func() -> void:
		if content == null:
			visible = false
		if gone != null:
			gone.queue_free())
	closed.emit()


## Lays the card out again when its content grows (a chart filled, a trace arrived).
func relayout() -> void:
	if is_open():
		_place.call_deferred(false)
