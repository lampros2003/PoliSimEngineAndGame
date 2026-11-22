extends RefCounted
## Stage S17.1: contrast, measured. The WCAG 2.1 contrast ratio between two colours, the
## colour one makes laid over another, the paper's tone at a place on the screen (the shader
## darkens it towards the corners), and, for a control on the screen, the colour its words are
## set in and the ground they stand on. The checks (tests/contrast_check.gd for the palette's
## pairs, tests/folds_check.gd for every popup and sheet as shown) hold text to TEXT, and text
## of LARGE_FROM pixels or more and marks that carry meaning to LARGE.

const Palette := preload("res://scripts/palette.gd")
const PoliticsPanel := preload("res://scripts/politics_panel.gd")

const TEXT := 4.5
const LARGE := 3.0
const LARGE_FROM := 18


static func _linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## Relative luminance (WCAG 2.1) of an opaque colour.
static func luminance(colour: Color) -> float:
	return 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)


## The contrast ratio of two opaque colours, 1 to 21.
static func ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## `top` laid over the opaque `under`.
static func over(top: Color, under: Color) -> Color:
	return Color(lerpf(under.r, top.r, top.a), lerpf(under.g, top.g, top.a), lerpf(under.b, top.b, top.a), 1.0)


## The ratio a piece of text must reach at `size_px`.
static func needed(size_px: int) -> float:
	return LARGE if size_px >= LARGE_FROM else TEXT


## The paper's tone at `uv` (0 to 1 across the screen), as Palette.PAPER_SHADER has it, at
## the dark end of its grain.
static func paper_at(uv: Vector2) -> Color:
	var c := (uv.clamp(Vector2.ZERO, Vector2.ONE) - Vector2(0.5, 0.5)) * Vector2(1.0, 1.25)
	var tone := Palette.PAPER.lerp(Palette.PAPER_EDGE, smoothstep(0.32, 0.92, c.length()) * 0.75)
	var grain := (0.022 + 0.016) * 0.5
	return Color(tone.r - grain, tone.g - grain, tone.b - grain, 1.0)


## The paper at its darkest, in a corner of the screen.
static func paper_darkest() -> Color:
	return paper_at(Vector2.ZERO)


## What a control paints behind its children, or a clear colour: a panel's or a button's
## flat box, a colour rectangle.
static func fill(control: Control) -> Color:
	var box: StyleBox = null
	if control is ColorRect:
		return (control as ColorRect).color
	if control is PanelContainer or control is Panel:
		box = control.get_theme_stylebox("panel")
	elif control is BaseButton:
		var button := control as BaseButton
		box = control.get_theme_stylebox("disabled" if button.disabled else ("pressed" if button.button_pressed else "normal"))
	elif control is LineEdit:
		box = control.get_theme_stylebox("normal")
	if box is StyleBoxFlat and (box as StyleBoxFlat).draw_center:
		return (box as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


## The opaque colour under a control's words: what it and the controls it sits in paint, down
## to the paper where it stands (at its darkest corner).
static func ground(control: Control) -> Color:
	var layers: Array[Color] = []
	var at: Node = control
	while at != null and at is Control:
		var colour := fill(at as Control)
		if colour.a > 0.0:
			layers.append(colour)
			if colour.a >= 0.999:
				break
		at = at.get_parent()
	var under := Color.BLACK
	if layers.is_empty() or layers[-1].a < 0.999:
		var view := control.get_viewport_rect().size
		var rect := control.get_global_rect()
		under = paper_at(rect.position / view)
		for corner in [Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
			var tone := paper_at((corner as Vector2) / view)
			if luminance(tone) < luminance(under):
				under = tone
	for i in range(layers.size() - 1, -1, -1):
		under = over(layers[i], under)
	return under


## How much of a control shows: its own and its parents' modulation.
static func shown(control: Control) -> Color:
	var m := Color.WHITE
	var at: Node = control
	while at != null and at is CanvasItem:
		m *= (at as CanvasItem).modulate
		if at == control:
			m *= (at as CanvasItem).self_modulate
		at = at.get_parent()
	return m


## The colours a control sets its words in, each with the pixel size: [[Color, int]]. A
## disabled button's are left out (a control that cannot be used is not held to a ratio).
static func inks(control: Control) -> Array:
	var out := []
	if control is Label:
		if (control as Label).text.strip_edges() != "":
			out.append([control.get_theme_color("font_color"), control.get_theme_font_size("font_size")])
	elif control is Button:
		var button := control as Button
		if button.text.strip_edges() != "" and not button.disabled:
			out.append([control.get_theme_color("font_pressed_color" if button.button_pressed else "font_color"), control.get_theme_font_size("font_size")])
	elif control is LineEdit:
		var edit := control as LineEdit
		if edit.text != "":
			out.append([control.get_theme_color("font_color"), control.get_theme_font_size("font_size")])
		elif edit.placeholder_text.strip_edges() != "":
			out.append([control.get_theme_color("font_placeholder_color"), control.get_theme_font_size("font_size")])
	elif control is RichTextLabel:
		var rich := control as RichTextLabel
		if rich.get_parsed_text().strip_edges() != "":
			var size_px := control.get_theme_font_size("normal_font_size")
			out.append([control.get_theme_color("default_color"), size_px])
			var tags := RegEx.create_from_string("\\[color=([^\\]]+)\\]")
			for found in tags.search_all(rich.text):
				out.append([Color.from_string(found.get_string(1), Color.MAGENTA), size_px])
	return out


## Every piece of text under `root` that is on screen and falls short: lines of
## "what: ink on ground, ratio against needed".
static func faults(root: Control) -> PackedStringArray:
	var out := PackedStringArray()
	var controls: Array = root.find_children("*", "Control", true, false)
	controls.append(root)
	for c in controls:
		var control := c as Control
		if not control.is_visible_in_tree() or control.size.x <= 0.0:
			continue
		var set_in := inks(control)
		if set_in.is_empty():
			continue
		var under := ground(control)
		var show := shown(control)
		for pair in set_in:
			var ink: Color = pair[0] * Color(show.r, show.g, show.b, 1.0)
			ink.a *= show.a
			var seen := over(ink, under)
			var got := ratio(seen, under)
			if got + 0.005 < needed(int(pair[1])):
				var words := ""
				if control is RichTextLabel:
					words = (control as RichTextLabel).get_parsed_text()
				else:
					words = str(control.get("text")) if str(control.get("text")) != "" else str(control.get("placeholder_text"))
				out.append("\"%s\" at %d px: #%s on #%s is %.2f to 1, under %.1f" % [
					words.left(36).replace("\n", " "), pair[1], seen.to_html(false), under.to_html(false), got, needed(int(pair[1]))])
	return out


## Every pair of ink and ground a walk of the screen cannot meet: the words the scripts draw
## themselves, the inks text is set in on every ground it may stand on, the theme's states
## under the pointer and pressed, and the marks that carry meaning. Each [what, ink, ground,
## the least ratio]; tests/contrast_check.gd holds them, so a change to the palette that
## breaks one fails.
static func pairs() -> Array:
	var dark := paper_darkest()
	var out := [
		# Words drawn by the scripts themselves.
		["a node's name, and an area's along the rim, on the board", Palette.INK, dark, TEXT],
		["a family's name by the ring of groups", Palette.MUTED, dark, TEXT],
		["the figure on the tag under the pointer", Palette.MUTED, Palette.CARD, TEXT],
		["the centre's caption", Palette.MUTED, Palette.CARD, TEXT],
		["a chart's scale", Palette.MUTED, Palette.CARD, TEXT],
		["a pennant's words, a good thing", Palette.CARD, Palette.BETTER, TEXT],
		["a pennant's words, a bad thing", Palette.CARD, Palette.WORSE, TEXT],
		["a pennant's words, neither", Palette.CARD, Palette.STEADY, TEXT],
		["a pennant's words, a question", Palette.INK, Palette.ASK, TEXT],
		# The theme's other states.
		["a button under the pointer", Palette.INK, Palette.HOVER, TEXT],
		["a button pressed", Palette.INK, Palette.CARD_DEEP, TEXT],
		["Next month", Palette.INK, Palette.OCHRE, TEXT],
		["Next month under the pointer", Palette.INK, Palette.PRIMARY_HOVER, TEXT],
		["Next month pressed", Palette.INK, Palette.PRIMARY_PRESSED, TEXT],
		["a link under the pointer", Palette.LINK_HOVER, Palette.CARD, TEXT],
		["a tooltip, and a level chosen", Palette.CARD, Palette.INK, TEXT],
		["the row chosen in a menu or the search's matches", Palette.INK, over(Color(Palette.OCHRE, 0.35), Palette.CARD), TEXT],
		# Marks that carry meaning.
		["an unmeasured link", over(Color(Palette.INK, 0.6), dark), dark, LARGE],
		["a group's approval gauge: the ink that keys what is filled", Palette.INK, dark, LARGE],
		["a policy's gauge", Palette.BLUE, dark, LARGE],
		["a change waiting, marked on a policy's gauge", Palette.PENDING, dark, LARGE],
		["a rise or a fall on a statistic's badge, good", Palette.CARD, Palette.GOOD, LARGE],
		["a rise or a fall on a statistic's badge, bad", Palette.CARD, Palette.BAD, LARGE],
		["a rise or a fall on a statistic's badge, neither", Palette.CARD, Palette.INK, LARGE],
		["a bar for a good change", Palette.SAGE, Palette.CARD, LARGE],
		["a bar for a bad change, and spending", Palette.BRICK, Palette.CARD, LARGE],
		["the edge of the row chosen in a list", Palette.INK, Palette.CARD, LARGE],
	]
	# The inks text is set in, on every ground a control may stand on.
	var inks := {"ink": Palette.INK, "muted": Palette.MUTED, "a link's blue": Palette.BLUE, "good": Palette.GOOD, "bad": Palette.BAD,
		"a change waiting": Palette.PENDING}
	var grounds := {"card stock": Palette.CARD, "the top bar": Palette.CARD_DEEP, "a raised panel": Palette.PANEL_RAISED,
		"a field": Palette.FIELD, "card under the pointer": Palette.HOVER, "the paper at its darkest": dark}
	for ink in inks:
		for under in grounds:
			out.append(["text in %s on %s" % [ink, under], inks[ink], grounds[under], TEXT])
	# A state's colour on the board: a statistic's ring, a link.
	for state in [["good", Palette.BETTER], ["bad", Palette.WORSE], ["neither", Palette.STEADY]]:
		out.append(["a statistic's ring and a link, %s" % state[0], state[1], dark, LARGE])
	for i in Palette.SERIES.size():
		out.append(["a chart's line %d" % (i + 1), Palette.SERIES[i], Palette.CARD, LARGE])
	for i in PoliticsPanel.BLOC_COLOURS.size():
		out.append(["bloc %d's seats" % (i + 1), PoliticsPanel.BLOC_COLOURS[i], Palette.CARD, LARGE])
	for under in grounds:
		out.append(["the ring round what has the keyboard, on %s" % under, Palette.FOCUS, grounds[under], LARGE])
	return out
