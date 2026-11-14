extends RefCounted
## Colours, type, sizes and the theme. One place, so every screen agrees.
##
## The look follows public-sector service and statistics design (GOV.UK and US Web Design
## System patterns, ONS chart colours): a light grey page, white sections with hairline
## rules and square corners, a navy masthead, serif headings and figures, tabular numbers,
## text links for row actions, and a strong keyboard focus outline. No real government's
## crown, logotype or typeface is used.

const BG := Color("#f3f2f1")
const PANEL := Color("#ffffff")
const PANEL_RAISED := Color("#f8f8f7")
const LINE := Color("#b1b4b6")
const RULE := Color("#d9d9d9")  # hairlines between table rows
const TEXT := Color("#0b0c0c")
const MUTED := Color("#484949")
const ACCENT := Color("#12436d")  # navy: the government's own rows, the masthead, focus
const MASTHEAD := Color("#12273f")
const LINK := Color("#1a65a6")
const LINK_HOVER := Color("#0f385c")
const FOCUS := Color("#ffdd00")
const PENDING := Color("#a35200")  # a change waiting for next month (amber, dark enough to read)
const GOOD := Color("#0f7a52")
const BAD := Color("#ca3535")
## ONS's categorical chart colours, in their order.
const SERIES := [Color("#12436d"), Color("#28a197"), Color("#801650"), Color("#f46a25")]

const FONT_SIZE := 15
const SMALL := 13
const TITLE := 22
const FIGURE := 30

const SANS_FILE := preload("res://fonts/PublicSans.ttf")
const SERIF_FILE := preload("res://fonts/SourceSerif4.ttf")


## A font at a weight, with tabular figures so columns of numbers line up.
static func font(file: FontFile, weight: int) -> FontVariation:
	var ts := TextServerManager.get_primary_interface()
	var f := FontVariation.new()
	f.base_font = file
	f.variation_opentype = {ts.name_to_tag("wght"): weight}
	f.opentype_features = {ts.name_to_tag("tnum"): 1}
	return f


static func panel_style(color: Color = PANEL, radius: int = 0, margin: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	if color == PANEL:
		box.border_color = LINE
		box.set_border_width_all(1)
	return box


static func _flat(bg: Color, border := Color.TRANSPARENT, bottom := 0, margin_h := 14, margin_v := 7) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_bottom = bottom
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v + 2 - bottom  # keeps the text still when the shadow goes
	box.anti_aliasing = false
	return box


static func _empty(margin_h := 4, margin_v := 4) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func _button_states(theme: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox,
		disabled: StyleBox, text: Color, text_hover: Color, text_disabled: Color) -> void:
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	for key in ["font_color", "font_focus_color"]:
		theme.set_color(key, type, text)
	for key in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(key, type, text_hover)
	theme.set_color("font_disabled_color", type, text_disabled)


## The default theme's icons are drawn for a dark background: redrawn in the text colour.
static func _recolour(icon: Texture2D, colour: Color) -> Texture2D:
	var image: Image = icon.get_image() if icon != null else null
	if image == null:  # an icon drawn from SVG at run time has no pixels to read here
		return icon
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(colour, p.a * p.v))
	return ImageTexture.create_from_image(image)


## A square box for check boxes: an outline, and filled inside when ticked.
static func _box_icon(ticked: bool, size := 18) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(0, 0, size, size), TEXT)
	image.fill_rect(Rect2i(2, 2, size - 4, size - 4), PANEL)
	if ticked:
		image.fill_rect(Rect2i(5, 5, size - 10, size - 10), ACCENT)
	return ImageTexture.create_from_image(image)


static func make_theme() -> Theme:
	var theme := Theme.new()
	var sans := font(SANS_FILE, 400)
	var sans_bold := font(SANS_FILE, 600)
	var serif := font(SERIF_FILE, 600)
	theme.default_font = sans
	theme.default_font_size = FONT_SIZE
	for type in ["Label", "RichTextLabel", "LineEdit", "TabContainer", "PopupMenu", "CheckBox", "TooltipLabel"]:
		theme.set_color("font_color" if type != "RichTextLabel" else "default_color", type, TEXT)
	theme.set_font("bold_font", "RichTextLabel", sans_bold)
	theme.set_color("font_selected_color", "LineEdit", TEXT)
	theme.set_color("selection_color", "LineEdit", FOCUS)
	theme.set_color("caret_color", "LineEdit", TEXT)

	# Buttons: secondary by default (grey with a shadow underneath, as on public services).
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = FOCUS
	focus.set_expand_margin_all(2)
	focus.shadow_color = TEXT
	focus.shadow_size = 2
	theme.set_stylebox("focus", "Button", focus)
	theme.set_font("font", "Button", font(SANS_FILE, 500))
	_button_states(theme, "Button", _flat(Color("#e8e8e6"), Color("#929191"), 2), _flat(Color("#d6d6d4"), Color("#929191"), 2),
		_flat(Color("#c9c9c7")), _flat(Color("#eeeeec")), TEXT, TEXT, Color("#9a9fa3"))

	# Primary: the one main action on a screen.
	theme.set_type_variation("Primary", "Button")
	_button_states(theme, "Primary", _flat(ACCENT, Color("#081c30"), 2), _flat(Color("#0d3354"), Color("#081c30"), 2),
		_flat(Color("#081c30")), _flat(ACCENT.lerp(BG, 0.6)), Color.WHITE, Color.WHITE, Color("#e8ecf0"))

	# Link: an action on a row ("Chart", "Why", "Undo", "Back"): text only.
	theme.set_type_variation("Link", "Button")
	_button_states(theme, "Link", _empty(), _empty(), _empty(), _empty(), LINK, LINK_HOVER, Color("#9a9fa3"))
	theme.set_font_size("font_size", "Link", SMALL + 1)

	# On the masthead: white text, and the main action in white.
	theme.set_type_variation("MastheadButton", "Button")
	var on_navy := _flat(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), 0)
	on_navy.set_border_width_all(1)
	var on_navy_hover := on_navy.duplicate()
	on_navy_hover.bg_color = Color(1, 1, 1, 0.12)
	var on_navy_down := on_navy.duplicate()
	on_navy_down.bg_color = Color(1, 1, 1, 0.22)
	var on_navy_off := on_navy.duplicate()
	on_navy_off.border_color = Color(1, 1, 1, 0.2)
	_button_states(theme, "MastheadButton", on_navy, on_navy_hover, on_navy_down, on_navy_off,
		Color.WHITE, Color.WHITE, Color(1, 1, 1, 0.4))
	theme.set_type_variation("MastheadPrimary", "Button")
	_button_states(theme, "MastheadPrimary", _flat(Color.WHITE, Color("#8fa3b8"), 2), _flat(Color("#e3e9ef"), Color("#8fa3b8"), 2),
		_flat(Color("#c8d3de")), _flat(Color(1, 1, 1, 0.25)), MASTHEAD, MASTHEAD, Color(1, 1, 1, 0.5))
	theme.set_font("font", "MastheadPrimary", sans_bold)
	theme.set_type_variation("MastheadLabel", "Label")
	theme.set_color("font_color", "MastheadLabel", Color.WHITE)
	theme.set_type_variation("MastheadTitle", "Label")
	theme.set_color("font_color", "MastheadTitle", Color.WHITE)
	theme.set_font("font", "MastheadTitle", serif)
	theme.set_font_size("font_size", "MastheadTitle", 21)
	theme.set_type_variation("Masthead", "PanelContainer")
	var masthead := StyleBoxFlat.new()
	masthead.bg_color = MASTHEAD
	masthead.content_margin_left = 20
	masthead.content_margin_right = 20
	masthead.content_margin_top = 10
	masthead.content_margin_bottom = 10
	theme.set_stylebox("panel", "Masthead", masthead)

	# Text styles.
	theme.set_type_variation("Title", "Label")
	theme.set_font("font", "Title", serif)
	theme.set_font_size("font_size", "Title", TITLE)
	theme.set_type_variation("Figure", "Label")
	theme.set_font("font", "Figure", serif)
	theme.set_font_size("font_size", "Figure", FIGURE)
	theme.set_type_variation("Heading", "Label")  # column and section headings in tables
	theme.set_font("font", "Heading", sans_bold)
	theme.set_font_size("font_size", "Heading", SMALL)
	theme.set_color("font_color", "Heading", MUTED)

	# Sections: white with a hairline border; headline figures carry a navy rule on top.
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_type_variation("HeadlineCard", "PanelContainer")
	var card := StyleBoxFlat.new()
	card.bg_color = PANEL
	card.border_color = ACCENT
	card.border_width_top = 4
	card.content_margin_left = 14
	card.content_margin_right = 10
	card.content_margin_top = 10
	card.content_margin_bottom = 8
	theme.set_stylebox("panel", "HeadlineCard", card)

	# Fields: white, a firm dark border.
	var field := StyleBoxFlat.new()
	field.bg_color = PANEL
	field.border_color = TEXT
	field.set_border_width_all(2)
	field.set_content_margin_all(6)
	var field_focus := focus.duplicate()
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	var field_off := field.duplicate()
	field_off.border_color = LINE
	field_off.bg_color = BG
	theme.set_stylebox("read_only", "LineEdit", field_off)

	# Tabs: the open one white, joined to its panel, with a navy rule on top.
	var tab_on := StyleBoxFlat.new()
	tab_on.bg_color = PANEL
	tab_on.border_color = ACCENT
	tab_on.border_width_top = 3
	tab_on.content_margin_left = 16
	tab_on.content_margin_right = 16
	tab_on.content_margin_top = 8
	tab_on.content_margin_bottom = 8
	var tab_off := tab_on.duplicate()
	tab_off.bg_color = Color("#e3e3e1")
	tab_off.border_color = Color("#e3e3e1")
	var tab_hover := tab_off.duplicate()
	tab_hover.bg_color = Color("#d6d6d4")
	tab_hover.border_color = Color("#d6d6d4")
	theme.set_stylebox("tab_selected", "TabContainer", tab_on)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_off)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	theme.set_stylebox("tab_focus", "TabContainer", focus)
	var tab_panel := panel_style()
	tab_panel.border_width_top = 0
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_color("font_selected_color", "TabContainer", TEXT)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)
	theme.set_font("font", "TabContainer", font(SANS_FILE, 600))

	# Menus, tooltips, dialogs, rules, scroll bars.
	var menu := panel_style(PANEL, 0, 6)
	theme.set_stylebox("panel", "PopupMenu", menu)
	theme.set_stylebox("hover", "PopupMenu", _flat(Color("#e8eef4"), Color.TRANSPARENT, 0, 8, 4))
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	var tip := panel_style(TEXT, 0, 8)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", Color.WHITE)
	theme.set_stylebox("panel", "AcceptDialog", panel_style(PANEL, 0, 20))
	var frame := StyleBoxFlat.new()
	frame.bg_color = MASTHEAD
	frame.expand_margin_left = 1
	frame.expand_margin_right = 1
	frame.expand_margin_bottom = 1
	frame.expand_margin_top = 34
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_constant("title_height", "Window", 34)
	theme.set_color("title_color", "Window", Color.WHITE)
	theme.set_font("title_font", "Window", sans_bold)
	theme.set_font_size("title_font_size", "Window", FONT_SIZE)
	for type in ["HSeparator", "VSeparator"]:
		var rule := StyleBoxLine.new()
		rule.color = LINE
		rule.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, rule)
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0)
		track.set_content_margin_all(3)
		var grab := StyleBoxFlat.new()
		grab.bg_color = LINE
		grab.set_content_margin_all(3)
		var grab_on := grab.duplicate()
		grab_on.bg_color = MUTED
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grab)
		theme.set_stylebox("grabber_highlight", type, grab_on)
		theme.set_stylebox("grabber_pressed", type, grab_on)

	# Icons: the defaults redrawn dark; square check boxes.
	var base := ThemeDB.get_default_theme()
	for pair in [["arrow", "OptionButton"], ["updown", "SpinBox"], ["up", "SpinBox"], ["down", "SpinBox"],
			["close", "Window"], ["submenu", "PopupMenu"], ["grabber", "HSplitContainer"], ["grabber", "VSplitContainer"]]:
		if base.has_icon(pair[0], pair[1]):
			theme.set_icon(pair[0], pair[1], _recolour(base.get_icon(pair[0], pair[1]), MUTED if pair[1] != "Window" else Color.WHITE))
	for type in ["CheckBox", "PopupMenu"]:
		theme.set_icon("checked", type, _box_icon(true))
		theme.set_icon("unchecked", type, _box_icon(false))
	theme.set_stylebox("normal", "CheckBox", _empty(2, 4))
	theme.set_stylebox("hover", "CheckBox", _empty(2, 4))
	theme.set_stylebox("pressed", "CheckBox", _empty(2, 4))
	theme.set_stylebox("hover_pressed", "CheckBox", _empty(2, 4))
	return theme


## Hairlines between the rows of a table laid out as a GridContainer.
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
