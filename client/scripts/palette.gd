extends RefCounted
## Colours, sizes and the theme. One place, so every screen agrees.

const BG := Color("#14181d")
const PANEL := Color("#1c2229")
const PANEL_RAISED := Color("#242c35")
const LINE := Color("#323c47")
const TEXT := Color("#e6e9ec")
const MUTED := Color("#94a0ab")
const ACCENT := Color("#4fb3bf")
const PENDING := Color("#e8a948")
const GOOD := Color("#5cbf7a")
const BAD := Color("#e06c6c")
const SERIES := [Color("#4fb3bf"), Color("#e8a948"), Color("#a98ee0"), Color("#7fc77a")]

const FONT_SIZE := 15
const SMALL := 13
const TITLE := 20
const FIGURE := 24


static func panel_style(color: Color = PANEL, radius: int = 6, margin: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	var normal := panel_style(PANEL_RAISED, 4, 6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate()
	hover.bg_color = PANEL_RAISED.lightened(0.12)
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT.darkened(0.45)
	var disabled := normal.duplicate()
	disabled.bg_color = PANEL
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = ACCENT
	focus.set_corner_radius_all(4)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	var field := panel_style(BG, 4, 6)
	field.border_color = LINE
	field.set_border_width_all(1)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", panel_style(PANEL_RAISED, 4, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "AcceptDialog", panel_style(PANEL, 6, 16))
	return theme
