extends Control
## Stage S13.2: a sheet laid over the board: the Budget, Parliament, a question put to the
## player, election night, help. Card stock on a dimmed board, a title in the display face
## and a Close; Esc or a click outside closes it when it may be closed.

const Palette := preload("res://scripts/palette.gd")
const Sound := preload("res://scripts/sound.gd")

signal closed

var title := ""
var body: VBoxContainer
var closable := true
## Space kept clear at the top of the window (the top bar).
var top_margin := 0.0
var width := 860.0
var card: PanelContainer
var _scroll: ScrollContainer
var _title: Label
var _close: Button
var _buttons: HBoxContainer
var _tween: Tween


func _init(heading: String, card_width := 860.0) -> void:
	title = heading
	width = card_width


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(Palette.INK, 0.3)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(event: InputEvent) -> void:
		if closable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(veil)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.card(0, 8, 2))
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var head_margin := MarginContainer.new()
	for side in ["left", "right"]:
		head_margin.add_theme_constant_override("margin_" + side, 32)
	head_margin.add_theme_constant_override("margin_top", 22)
	head_margin.add_theme_constant_override("margin_bottom", 8)
	column.add_child(head_margin)
	var head := HBoxContainer.new()
	head_margin.add_child(head)
	_title = Label.new()
	_title.text = title
	_title.theme_type_variation = "Title"
	_title.add_theme_font_size_override("font_size", 32)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	_close = Button.new()
	_close.text = "Close  ✕"
	_close.theme_type_variation = "Link"
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.pressed.connect(close)
	_close.visible = closable
	head.add_child(_close)
	# A double ink rule under the title, as on a printed sheet.
	var rules := Control.new()
	rules.custom_minimum_size = Vector2(0, 8)
	rules.draw.connect(func() -> void:
		rules.draw_line(Vector2(32, 1), Vector2(rules.size.x - 32, 1), Palette.INK, 2.0)
		rules.draw_line(Vector2(32, 6), Vector2(rules.size.x - 32, 6), Palette.INK, 1.0))
	column.add_child(rules)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 26)
	_scroll.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.custom_minimum_size = Vector2(width - 64.0, 0)
	margin.add_child(body)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	var button_margin := MarginContainer.new()
	for side in ["left", "right"]:
		button_margin.add_theme_constant_override("margin_" + side, 32)
	button_margin.add_theme_constant_override("margin_bottom", 26)
	button_margin.add_child(_buttons)
	button_margin.visible = false
	column.add_child(button_margin)
	resized.connect(_place)


func set_closable(on: bool) -> void:
	closable = on
	if _close != null:
		_close.visible = on


## Adds a button under the body (the answers to a question).
func add_action(text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "Primary" if primary else ""
	button.pressed.connect(action)
	_buttons.add_child(button)
	_buttons.get_parent().visible = true
	return button


## Adds bbcode text to the body.
func add_text(bbcode: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.selection_enabled = true
	text.text = bbcode
	text.custom_minimum_size = Vector2(width - 64.0, 0)
	body.add_child(text)
	return text


func open() -> void:
	if not visible:
		Sound.play("open")
	visible = true
	_place.call_deferred()
	# Wrapped text settles its height a frame later: place the card again then.
	get_tree().process_frame.connect(func() -> void: get_tree().process_frame.connect(_place, CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.14)


func _place() -> void:
	if card == null:
		return
	var view := size
	var room := view.y - top_margin - 48.0 - 140.0
	_scroll.custom_minimum_size = Vector2(width, minf(body.get_combined_minimum_size().y + 44.0, room))
	card.reset_size()
	var box := card.get_combined_minimum_size()
	card.size = box
	card.position = Vector2(roundf((view.x - box.x) / 2.0), roundf(top_margin + maxf(18.0, (view.y - top_margin - box.y) / 2.0)))


func relayout() -> void:
	_place.call_deferred()
	get_tree().process_frame.connect(func() -> void: get_tree().process_frame.connect(_place, CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)


func close() -> void:
	if not visible:
		return
	Sound.play("close")
	visible = false
	closed.emit()
