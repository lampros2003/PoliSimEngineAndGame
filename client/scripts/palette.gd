extends RefCounted
## Colours, type, sizes, card stock and the theme. One place, so every screen agrees.
##
## Stage S13.2: pictorial statistics, the mid-century public-information print tradition.
## Warm paper with grain, a few flat inks (navy for text and line work, blue, brick, ochre,
## sage), card stock a shade lighter than the paper with a firm ink edge and a hard offset
## shadow, rules in ink. Ochre is the one accent: "you can act here, a change is waiting".
## Good and bad are sage and brick, always with a sign or arrow beside the colour. Titles,
## node labels and big numerals in Jost; text and figures in IBM Plex Sans with tabular
## figures. Icons are white silhouettes from game-icons.net, tinted when drawn.

const PAPER := Color("#efe6d2")
const PAPER_EDGE := Color("#d9ccae")  # the vignette's edge
const CARD := Color("#f8f2e4")
const CARD_DEEP := Color("#e8dcc1")  # a band of card stock a shade darker (the top bar)
const INK := Color("#1c2733")
const BLUE := Color("#1f4e79")
const BRICK := Color("#b0412c")
const OCHRE := Color("#d99a27")
const SAGE := Color("#5f7f55")

# The names the panels reused from S12 read.
const BG := PAPER
const PANEL := CARD
const PANEL_RAISED := Color("#f1e9d6")
const LINE := Color("#7d8590")  # an ink rule, thinned
const RULE := Color("#cdbf9f")  # rules between rows: ink on paper, light
const TEXT := INK
const MUTED := Color("#55606c")
const ACCENT := BLUE
const PENDING := Color("#94600c")  # ochre dark enough to read as text
const GOOD := Color("#4b6a42")
const BAD := BRICK
const SHADOW := Color("#1c2733")
const SERIES := [BLUE, BRICK, Color("#b07a12"), SAGE]

const FONT_SIZE := 15
const SMALL := 14
const CAPS := 13  # tracked capitals for small labels
const TITLE := 26
const FIGURE := 34

const TEXT_FILE := preload("res://fonts/IBMPlexSans.ttf")
const DISPLAY_FILE := preload("res://fonts/Jost.ttf")
## Kept for the panels that name the old constants.
const SANS_FILE := TEXT_FILE
const SERIF_FILE := DISPLAY_FILE

const PAPER_SHADER := """
shader_type canvas_item;
uniform vec4 paper : source_color;
uniform vec4 edge : source_color;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 px = floor(FRAGCOORD.xy);
	float fine = hash(px) - 0.5;
	float coarse = hash(floor(px / 3.0) + 17.0) - 0.5;
	vec2 c = (UV - 0.5) * vec2(1.0, 1.25);
	float vignette = smoothstep(0.32, 0.92, length(c));
	vec3 tone = mix(paper.rgb, edge.rgb, vignette * 0.75);
	COLOR = vec4(tone + fine * 0.022 + coarse * 0.016, 1.0);
}
"""

static var _fonts := {}


## A font at a weight, with tabular figures so columns of numbers line up.
static func font(file: FontFile, weight: int, spacing := 0) -> FontVariation:
	var key := "%s/%d/%d" % [file.resource_path, weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var ts := TextServerManager.get_primary_interface()
	var f := FontVariation.new()
	f.base_font = file
	f.variation_opentype = {ts.name_to_tag("wght"): weight}
	f.opentype_features = {ts.name_to_tag("tnum"): 1}
	if spacing != 0:
		f.spacing_glyph = spacing
	_fonts[key] = f
	return f


static func text(weight := 400) -> FontVariation:
	return font(TEXT_FILE, weight)


static func display(weight := 500, spacing := 0) -> FontVariation:
	return font(DISPLAY_FILE, weight, spacing)


## Card stock: a shade lighter than the paper, a firm ink edge and a hard shadow down and
## to the right, like a printed plate.
static func card(margin := 20, shadow := 6, border := 2, colour := CARD) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.border_color = INK
	box.set_border_width_all(border)
	box.set_content_margin_all(margin)
	if shadow > 0:
		box.shadow_color = Color(SHADOW, 0.92)
		box.shadow_size = 1
		box.shadow_offset = Vector2(shadow, shadow)
	box.anti_aliasing = false
	return box


static func panel_style(color: Color = PANEL, _radius: int = 0, margin: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	return box


static func _flat(bg: Color, border: Color, width := 2, margin_h := 14, margin_v := 6, shadow := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing = false
	if shadow > 0:
		box.shadow_color = SHADOW
		box.shadow_size = 1
		box.shadow_offset = Vector2(shadow, shadow)
	return box


static func _empty(margin_h := 4, margin_v := 4) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func _button_states(theme: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox,
		disabled: StyleBox, text_colour: Color, text_hover: Color, text_disabled: Color) -> void:
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	for key in ["font_color", "font_focus_color"]:
		theme.set_color(key, type, text_colour)
	for key in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(key, type, text_hover)
	theme.set_color("font_disabled_color", type, text_disabled)
	for key in ["icon_normal_color", "icon_focus_color"]:
		theme.set_color(key, type, text_colour)
	for key in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(key, type, text_hover)
	theme.set_color("icon_disabled_color", type, text_disabled)


## A small square drawn in ink: ticked, an ink block inside.
static func _box_icon(ticked: bool, size := 18) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(0, 0, size, size), INK)
	image.fill_rect(Rect2i(2, 2, size - 4, size - 4), CARD)
	if ticked:
		image.fill_rect(Rect2i(5, 5, size - 10, size - 10), INK)
	return ImageTexture.create_from_image(image)


## A small solid triangle, pointing down (menus) or up/down (spin boxes).
static func _triangle(size: int, up: bool, colour: Color) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in size:
		var row := (size - 1 - y) if up else y
		var half := int((size - 1 - row) * 0.5)
		for x in range(size / 2 - half, size / 2 + half + 1):
			if row < size * 0.7 and x >= 0 and x < size:
				image.set_pixel(x, y if not up else y, colour)
	return ImageTexture.create_from_image(image)


static func make_theme() -> Theme:
	var theme := Theme.new()
	var body := text(400)
	var strong := text(600)
	theme.default_font = body
	theme.default_font_size = FONT_SIZE
	for type in ["Label", "LineEdit", "PopupMenu", "CheckBox", "TooltipLabel", "OptionButton"]:
		theme.set_color("font_color", type, INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_font("bold_font", "RichTextLabel", strong)
	theme.set_font("normal_font", "RichTextLabel", body)
	theme.set_color("selection_color", "RichTextLabel", Color(OCHRE, 0.45))
	theme.set_color("font_selected_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", Color(OCHRE, 0.5))
	theme.set_color("caret_color", "LineEdit", INK)

	# Buttons: card stock with an ink edge; pressed sinks into its shadow.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = OCHRE
	focus.set_expand_margin_all(3)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_font("font", "Button", text(500))
	_button_states(theme, "Button", _flat(CARD, INK, 2, 14, 6, 3), _flat(Color("#fbf3dc"), INK, 2, 14, 6, 3),
		_flat(CARD_DEEP, INK, 2, 14, 6, 0), _flat(PAPER, LINE, 2, 14, 6, 0), INK, INK, LINE)
	# Primary: the one main action (Next month); ochre, the colour of acting.
	theme.set_type_variation("Primary", "Button")
	_button_states(theme, "Primary", _flat(OCHRE, INK, 2, 18, 7, 4), _flat(Color("#e6ac43"), INK, 2, 18, 7, 4),
		_flat(Color("#c4871b"), INK, 2, 18, 7, 0), _flat(Color(OCHRE, 0.35), Color(INK, 0.35), 2, 18, 7, 0), INK, INK, Color(INK, 0.45))
	theme.set_font("font", "Primary", display(600, 1))
	theme.set_font_size("font_size", "Primary", 16)
	# Quiet: secondary actions on the top bar, text with an ink edge only on hover.
	theme.set_type_variation("Quiet", "Button")
	_button_states(theme, "Quiet", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2, 8, 6), _flat(Color(INK, 0.06), INK, 2, 8, 6),
		_flat(Color(INK, 0.12), INK, 2, 8, 6), _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2, 8, 6), INK, INK, LINE)
	theme.set_font("font", "Quiet", display(500, 1))
	theme.set_font_size("font_size", "Quiet", 15)
	theme.set_constant("h_separation", "Quiet", 6)
	theme.set_constant("icon_max_width", "Quiet", 20)
	# Link: an action inside a card ("Undo", "Back"): blue text.
	theme.set_type_variation("Link", "Button")
	# Stage S13.6: underlined on hover, so every link answers the pointer.
	var underline := _flat(Color(0, 0, 0, 0), Color("#0f2f4d"), 0, 4, 4)
	underline.border_width_bottom = 1
	_button_states(theme, "Link", _empty(), underline, underline, _empty(), BLUE, Color("#0f2f4d"), LINE)
	theme.set_font("font", "Link", text(600))
	theme.set_font_size("font_size", "Link", SMALL)
	# Stage S13.6: a line of the month's report, or a row in a sheet: a tint under the pointer.
	theme.set_type_variation("ReportLine", "Button")
	_button_states(theme, "ReportLine", _empty(6, 3), _flat(Color(INK, 0.07), Color(0, 0, 0, 0), 0, 6, 3),
		_flat(Color(INK, 0.13), Color(0, 0, 0, 0), 0, 6, 3), _empty(6, 3), INK, INK, MUTED)
	theme.set_font("font", "ReportLine", text(500))
	# Chip: a figure on the top bar that opens its popup.
	theme.set_type_variation("Chip", "Button")
	_button_states(theme, "Chip", _empty(10, 2), _flat(Color(INK, 0.06), Color(INK, 0.0), 0, 10, 2),
		_flat(Color(INK, 0.12), Color(INK, 0.0), 0, 10, 2), _empty(10, 2), INK, INK, INK)

	# Text styles.
	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", display(500))
	theme.set_font_size("font_size", "Title", TITLE)
	theme.set_type_variation("Figure", "Label")
	theme.set_font("font", "Figure", display(500))
	theme.set_font_size("font_size", "Figure", FIGURE)
	theme.set_type_variation("Heading", "Label")  # small tracked capitals over a section
	theme.set_font("font", "Heading", display(600, 1))
	theme.set_font_size("font_size", "Heading", CAPS)
	theme.set_color("font_color", "Heading", MUTED)
	theme.set_type_variation("Muted", "Label")
	theme.set_color("font_color", "Muted", MUTED)
	theme.set_font_size("font_size", "Muted", SMALL)

	theme.set_stylebox("panel", "PanelContainer", _empty(0, 0))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", card())

	# Fields: card stock, an ink edge; ochre when focused.
	var field := _flat(Color("#fffaf0"), INK, 2, 8, 4)
	var field_focus := _flat(Color("#fffaf0"), OCHRE, 2, 8, 4)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", _flat(PAPER, LINE, 2, 8, 4))
	theme.set_font("font", "LineEdit", text(500))

	# Sliders: an ink track, an ochre grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.25)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var filled := StyleBoxFlat.new()
	filled.bg_color = INK
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", _grabber(false))
	theme.set_icon("grabber_highlight", "HSlider", _grabber(true))
	theme.set_stylebox("focus", "HSlider", focus)  # stage S13.6: the keyboard's place, in ochre

	# Menus, tooltips, option buttons.
	theme.set_stylebox("panel", "PopupMenu", card(6, 4))
	theme.set_stylebox("hover", "PopupMenu", _flat(Color(OCHRE, 0.35), Color(0, 0, 0, 0), 0, 8, 4))
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	theme.set_color("font_separator_color", "PopupMenu", MUTED)
	theme.set_stylebox("panel", "TooltipPanel", _flat(INK, INK, 0, 10, 6))
	theme.set_color("font_color", "TooltipLabel", CARD)
	theme.set_font_size("font_size", "TooltipLabel", SMALL)
	theme.set_icon("arrow", "OptionButton", _triangle(12, false, INK))
	for type in ["CheckBox", "PopupMenu"]:
		theme.set_icon("checked", type, _box_icon(true))
		theme.set_icon("unchecked", type, _box_icon(false))
		theme.set_icon("radio_checked", type, _box_icon(true))
		theme.set_icon("radio_unchecked", type, _box_icon(false))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckBox", _empty(2, 4))
	theme.set_constant("h_separation", "CheckBox", 10)

	for type in ["HSeparator", "VSeparator"]:
		var rule := StyleBoxLine.new()
		rule.color = INK
		rule.thickness = 2
		rule.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, rule)
	for type in ["VScrollBar", "HScrollBar"]:
		var lane := StyleBoxFlat.new()
		lane.bg_color = Color(0, 0, 0, 0)
		lane.set_content_margin_all(3)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(INK, 0.35)
		grab.set_content_margin_all(3)
		var grab_on := grab.duplicate()
		grab_on.bg_color = INK
		theme.set_stylebox("scroll", type, lane)
		theme.set_stylebox("grabber", type, grab)
		theme.set_stylebox("grabber_highlight", type, grab_on)
		theme.set_stylebox("grabber_pressed", type, grab_on)
	# Spin boxes: the field only, with small ink arrows.
	theme.set_icon("updown", "SpinBox", _updown())
	return theme


static func _grabber(hot: bool) -> Texture2D:
	var size := 18
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(3, 0, size - 6, size), INK)
	image.fill_rect(Rect2i(5, 2, size - 10, size - 4), Color("#e6ac43") if hot else OCHRE)
	return ImageTexture.create_from_image(image)


static func _updown() -> Texture2D:
	var w := 12
	var h := 20
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for row in 5:
		for x in range(w / 2 - row, w / 2 + row):
			image.set_pixel(x, 3 + row, INK)
			image.set_pixel(x, h - 4 - row, INK)
	return ImageTexture.create_from_image(image)


## The paper the board and every screen sits on: a full-rect node with grain and vignette.
static func paper() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = PAPER
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = PAPER_SHADER
	material.shader = shader
	material.set_shader_parameter("paper", PAPER)
	material.set_shader_parameter("edge", PAPER_EDGE)
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## An icon from client/icons by name (game-icons.net silhouettes, drawn white so a colour
## can tint them); the generic cog for a name that has none.
static func icon(name: String) -> Texture2D:
	var path := "res://icons/%s.svg" % name
	return load(path if name != "" and ResourceLoader.exists(path) else "res://icons/policy.svg")


## Ink rules between the rows of a table laid out as a GridContainer.
static func rule_rows(grid: GridContainer) -> void:
	grid.sort_children.connect(grid.queue_redraw)
	grid.draw.connect(func() -> void:
		var gap := grid.get_theme_constant("v_separation")
		var count := grid.get_child_count()
		for start in range(0, count, grid.columns):
			var bottom := 0.0
			for i in range(start, mini(start + grid.columns, count)):
				var child := grid.get_child(i) as Control
				if child != null and child.visible:
					bottom = maxf(bottom, child.position.y + child.size.y)
			if bottom > 0.0 and start + grid.columns < count:
				var y := floorf(bottom + gap / 2.0) + 0.5
				grid.draw_line(Vector2(0, y), Vector2(grid.size.x, y), RULE, 1.0))


## A tracked-capitals label for a small heading.
static func caps(words: String) -> Label:
	var label := Label.new()
	label.text = words.to_upper()
	label.theme_type_variation = "Heading"
	return label
