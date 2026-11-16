extends HBoxContainer
## Stage S15.1: the Add policy sheet's content. The policy areas down the side, each with how
## many policies it has to add (greyed when it has none); for the area chosen, each policy not
## in force with its pictogram, a line on what it does, what the smallest step in would cost
## in political capital, whether the Commons would pass it, and who would cheer and who would
## boo (the groups the effects table has it move most). Choosing one sends `chosen`; the
## screen (main.gd) closes the sheet and opens that policy's popup at its first step.

const Palette := preload("res://scripts/palette.gd")

signal chosen(key: String)

## For the checks: the area shown and the policy keys it lists, in order.
var area := ""
var keys: PackedStringArray = []
## Rows by policy key, for the checks and to scroll to one.
var rows := {}
var _areas: VBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _note: Label
var _area_buttons := {}
## Set by the screen: area name -> [{key, label, icon, line, cost, vote, passes, cheer, boo}].
var items := {}
var _order: Array = []  # [name, icon] of every area, in board order


func _ready() -> void:
	add_theme_constant_override("separation", 24)


## `areas` is [[name, icon texture]] in board order; `by_area` the items of each.
func build(areas: Array, by_area: Dictionary) -> void:
	_order = areas
	items = by_area
	_areas = VBoxContainer.new()
	_areas.name = "areas"
	_areas.add_theme_constant_override("separation", 2)
	_areas.custom_minimum_size.x = 230
	add_child(_areas)
	var group := ButtonGroup.new()
	for a in areas:
		var name := str(a[0])
		var count: int = by_area.get(name, []).size()
		var button := Button.new()
		button.name = "area_" + name.to_lower().replace(" ", "_")
		button.theme_type_variation = "ReportLine"
		button.toggle_mode = true
		button.button_group = group
		button.icon = a[1]
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 22)
		button.add_theme_color_override("icon_normal_color", Palette.INK)
		button.add_theme_color_override("icon_disabled_color", Palette.LINE)
		button.text = "%s   %d" % [name, count] if count > 0 else name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = count == 0
		button.tooltip_text = "%d %s to add" % [count, "policy" if count == 1 else "policies"] if count > 0 else "Every policy of this area is in force"
		button.pressed.connect(func() -> void: show_area(name))
		_areas.add_child(button)
		_area_buttons[name] = button
	add_child(_rule())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_title = Label.new()
	_title.theme_type_variation = "Title"
	_title.add_theme_font_size_override("font_size", 22)
	right.add_child(_title)
	_note = Label.new()
	_note.theme_type_variation = "Muted"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 520
	_note.text = "Not in force. Choose one to set it, see what it would do in a year, and put it to the Commons."
	right.add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	# Rows settle their height once their words have wrapped: the list fits itself again then.
	_list.minimum_size_changed.connect(func() -> void:
		if is_inside_tree():
			_fit_list.call_deferred())
	var first := ""
	for a in areas:
		if not by_area.get(str(a[0]), []).is_empty():
			first = str(a[0])
			break
	show_area(first if first != "" else (str(areas[0][0]) if not areas.is_empty() else ""))


## The list's height: as tall as the area's policies, at least the areas' column, at most
## what the sheet leaves for it (`room`); a longer list scrolls.
func fit(room: float) -> void:
	_room = clampf(room, 240.0, 900.0)
	_fit_list()


var _room := 600.0


func _fit_list() -> void:
	var tall := maxf(_list.get_combined_minimum_size().y, _areas.get_combined_minimum_size().y - 90.0)
	var want := Vector2(560, minf(tall + 4.0, _room))
	if want.is_equal_approx(_scroll.custom_minimum_size):
		return
	_scroll.custom_minimum_size = want
	get_tree().call_group("popups", "relayout")


func show_area(name: String) -> void:
	area = name
	keys.clear()
	rows.clear()
	if _area_buttons.has(name):
		(_area_buttons[name] as Button).button_pressed = true  # the group lets the others go
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_title.text = name
	var list: Array = items.get(name, [])
	_note.visible = not list.is_empty()
	if list.is_empty():
		var none := Label.new()
		none.text = "Every policy of this area is in force."
		none.theme_type_variation = "Muted"
		_list.add_child(none)
	for item in list:
		keys.append(str(item["key"]))
		var row := _row(item)
		rows[str(item["key"])] = row
		_list.add_child(row)
	_scroll.scroll_vertical = 0
	if is_inside_tree():
		_fit_list.call_deferred()


## Shows a policy's area and scrolls its row into view.
func show_policy(key: String) -> void:
	for name in items:
		for item in items[name]:
			if str(item["key"]) == key:
				show_area(name)
				var row: Control = rows.get(key)
				if row != null:
					row.grab_focus.call_deferred()
					_scroll.ensure_control_visible.call_deferred(row)
				return


func _rule() -> Control:
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(2, 0)
	rule.draw.connect(func() -> void: rule.draw_line(Vector2(1, 0), Vector2(1, rule.size.y), Color(Palette.INK, 0.35), 1.0))
	return rule


func _row(item: Dictionary) -> Button:
	var button := Button.new()
	button.name = "add_" + str(item["key"]).trim_prefix("policy:")
	button.theme_type_variation = "ReportLine"
	button.focus_mode = Control.FOCUS_ALL
	var key := str(item["key"])
	button.pressed.connect(func() -> void: chosen.emit(key))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -8
	button.add_child(box)
	var icon := TextureRect.new()
	icon.texture = item["icon"]
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.self_modulate = Palette.INK
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(words)
	var name := Label.new()
	name.text = str(item["label"])
	name.add_theme_font_override("font", Palette.display(500))
	name.add_theme_font_size_override("font_size", 19)
	words.add_child(name)
	var line := Label.new()
	line.text = str(item["line"])
	line.theme_type_variation = "Muted"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 240
	words.add_child(line)
	var cheer: Array = item.get("cheer", [])
	var boo: Array = item.get("boo", [])
	if not cheer.is_empty() or not boo.is_empty():
		var who := RichTextLabel.new()
		who.bbcode_enabled = true
		who.fit_content = true
		who.scroll_active = false
		who.mouse_filter = Control.MOUSE_FILTER_IGNORE
		who.add_theme_font_size_override("normal_font_size", Palette.SMALL)
		who.add_theme_font_size_override("bold_font_size", Palette.SMALL)
		var parts := PackedStringArray()
		if not cheer.is_empty():
			parts.append("[color=#%s][b]Cheer:[/b] %s[/color]" % [Palette.GOOD.to_html(false), ", ".join(cheer)])
		if not boo.is_empty():
			parts.append("[color=#%s][b]Boo:[/b] %s[/color]" % [Palette.BAD.to_html(false), ", ".join(boo)])
		who.text = "    ".join(parts)
		words.add_child(who)
	elif bool(item.get("pending", false)):
		var wait := Label.new()
		wait.text = "Who would cheer and who would boo: measuring…"
		wait.theme_type_variation = "Muted"
		words.add_child(wait)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	side.custom_minimum_size.x = 160
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(side)
	for spec in [[str(item.get("cost", "")), Palette.PENDING], [str(item.get("vote", "")), Palette.GOOD if item.get("passes", true) else Palette.BAD]]:
		if spec[0] == "":
			continue
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", spec[1])
		l.add_theme_font_override("font", Palette.text(600))
		l.add_theme_font_size_override("font_size", Palette.SMALL)
		side.add_child(l)
	# The row is as tall as its words.
	box.minimum_size_changed.connect(func() -> void: button.custom_minimum_size.y = box.get_combined_minimum_size().y + 16.0)
	button.custom_minimum_size.y = 76
	return button
