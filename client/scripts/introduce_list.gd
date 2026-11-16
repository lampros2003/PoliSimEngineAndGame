extends VBoxContainer
## Stage S13.5: an area's "introduce a policy" popup: the area's policies not in force, each
## with its pictogram, its name, a line on what it does and the political capital the
## smallest step in would cost. Choosing one opens its policy popup, ready to introduce.

const Palette := preload("res://scripts/palette.gd")

signal chosen(key: String)

var area := ""
## For the checks: the policy keys listed, in order.
var keys: PackedStringArray = []


## `items`: [{key, label, icon (Texture2D), line, cost (text)}].
func build(area_name: String, area_icon: Texture2D, items: Array) -> void:
	area = area_name
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var badge := TextureRect.new()
	badge.texture = area_icon
	badge.custom_minimum_size = Vector2(56, 56)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = Palette.INK
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	titles.add_child(Palette.caps(area_name))
	var title := Label.new()
	title.text = "Introduce a policy"
	title.theme_type_variation = "Title"
	titles.add_child(title)
	var note := Label.new()
	note.text = "These are not in force. Choose one to set it, see what it would do in a year, and put it to the Commons."
	note.theme_type_variation = "Muted"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	add_child(note)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	for item in items:
		keys.append(str(item["key"]))
		var button := Button.new()
		button.name = "introduce_" + str(item["key"]).trim_prefix("policy:")
		button.theme_type_variation = "ReportLine"
		button.custom_minimum_size = Vector2(0, 74)
		var key := str(item["key"])
		button.pressed.connect(func() -> void: chosen.emit(key))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		button.add_child(row)
		var icon := TextureRect.new()
		icon.texture = item["icon"]
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.self_modulate = Palette.INK
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(words)
		var name := Label.new()
		name.text = str(item["label"])
		name.add_theme_font_override("font", Palette.display(500))
		name.add_theme_font_size_override("font_size", 19)
		words.add_child(name)
		var line := Label.new()
		line.text = str(item["line"])
		line.theme_type_variation = "Muted"
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(line)
		var cost := Label.new()
		cost.text = str(item["cost"])
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.custom_minimum_size.x = 190
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.add_theme_color_override("font_color", Palette.PENDING)
		cost.add_theme_font_override("font", Palette.text(600))
		cost.add_theme_font_size_override("font_size", Palette.SMALL)
		row.add_child(cost)
		list.add_child(button)
	if items.is_empty():
		var none := Label.new()
		none.text = "Every policy of this area is in force."
		none.theme_type_variation = "Muted"
		add_child(none)
