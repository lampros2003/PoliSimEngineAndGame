extends VBoxContainer
## Stage S13.4: an interest group's popup. Its name and pictogram; its approval (the share
## of its likely voters who back the government) large, with the month's change; its
## history against the national rating; its share of the electorate as a hundred figures;
## what is moving it (the five drivers of its vote, as signed bars with plain names); the
## policies that move it most (each opens its popup); and eight of its households, drawn as
## figures, each opening to its account for the year.

const Palette := preload("res://scripts/palette.gd")
const Chart := preload("res://scripts/chart.gd")
const Bar := preload("res://scripts/bar.gd")

## A board key to open ("policy:..."), or a household record to show.
signal follow(target: String)
signal household_opened(record: Dictionary)

var fmt: RefCounted
## True for two columns (set before build).
var wide := false
var key := ""  # the board's group key
var row := ""  # its approval row
var share_row := ""
var entry := {}  # the approval row's catalogue entry
var index := -1  # its place in the group dimension
var chart: Chart
## For tests: what is shown.
var approval_text := ""
var drivers_shown: Array = []  # [plain name, value]
var records: Array = []  # the households shown
var estimate := ""  # stage S13.5: where an estimated group's membership comes from
var _note := ""
var _figure: Label
var _change: Label
var _note_label: Label
var _share_label: Label
var _people: Control
var _share := 0.0
var _drivers: GridContainer
var _homes: GridContainer
var _homes_note: Label
var _stance_note: Label
## For the checks: what the stance line says ("" for a group no stance moves).
var stance_text := ""


## Stage S15.3: the stance a belief group answers to, and where the government stands on it.
func set_stance(words: String) -> void:
	var first := stance_text == "" and words != ""
	stance_text = words
	if _stance_note != null:
		_stance_note.text = words
		_stance_note.visible = words != ""
		# A group of belief opens on what moves it: where the government stands.
		var fold := find_child("fold_what_is_moving_them", false, false)
		if first and fold != null and fold.has_meta("fold"):
			for other in get_children():
				if other != fold and other.has_meta("fold"):
					(other.get_meta("fold") as Callable).call(false)
			(fold.get_meta("fold") as Callable).call(true)


## `node` the board's group node; `drivers` [[plain name, value name]] in order; `movers`
## [[policy key, label, signed strength, measured]], strongest first.
func build(node: Dictionary, the_entry: Dictionary, drivers: Array, movers: Array) -> void:
	key = str(node["key"])
	row = str(node["row"])
	share_row = str(node.get("share", ""))
	entry = the_entry
	_note = str(node.get("note", ""))
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var badge := TextureRect.new()
	badge.texture = node.get("icon")
	badge.custom_minimum_size = Vector2(56, 56)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = Palette.INK
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(Palette.caps("Group of voters"))
	var title := Label.new()
	title.text = str(node["label"])
	title.theme_type_variation = "Title"
	titles.add_child(title)
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 16)
	add_child(figures)
	_figure = Label.new()
	_figure.name = "approval"
	_figure.theme_type_variation = "Figure"
	_figure.add_theme_font_size_override("font_size", 44)
	figures.add_child(_figure)
	var side := VBoxContainer.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	side.add_theme_constant_override("separation", 0)
	figures.add_child(side)
	# Stage S13.5: approval counts only those who would vote, as a poll does.
	side.add_child(_muted("of those who would vote back the government"))
	_change = Label.new()
	_change.add_theme_font_override("font", Palette.text(600))
	side.add_child(_change)
	_note_label = _muted("")
	_note_label.visible = false
	add_child(_note_label)
	# Stage S14.1: one column of sections, one open at a time, so the popup fits the screen.
	chart = Chart.new()
	chart.fmt = fmt
	chart.entry = entry
	chart.custom_minimum_size = Vector2(0, 180)
	add_child(Palette.fold("History", chart, true))
	var moving := VBoxContainer.new()
	moving.add_theme_constant_override("separation", 8)
	_drivers = GridContainer.new()
	_drivers.columns = 3
	_drivers.add_theme_constant_override("h_separation", 12)
	_drivers.add_theme_constant_override("v_separation", 8)
	moving.add_child(_drivers)
	for d in drivers:
		var name := Label.new()
		name.text = str(d[0])
		name.custom_minimum_size = Vector2(240, 0)
		_drivers.add_child(name)
		var bar := Bar.new()
		bar.custom_minimum_size = Vector2(150, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.up_colour = Palette.SAGE
		bar.down_colour = Palette.BRICK
		_drivers.add_child(bar)
		var amount := Label.new()
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.custom_minimum_size = Vector2(80, 0)
		_drivers.add_child(amount)
	# Stage S15.3: for a belief group, which stance its "Where the government stands" reads.
	_stance_note = _muted("")
	_stance_note.name = "stance_note"
	_stance_note.add_theme_color_override("font_color", Palette.INK)
	_stance_note.visible = false
	moving.add_child(_stance_note)
	moving.add_child(_muted("Each is a pull on their vote, for the government (right) or against it (left), from where things stood at the last election."))
	add_child(Palette.fold("What is moving them", moving))
	var share := VBoxContainer.new()
	share.add_theme_constant_override("separation", 8)
	_share_label = _muted("")
	share.add_child(_share_label)
	_people = Control.new()
	_people.custom_minimum_size = Vector2(0, 4 * 26)
	_people.draw.connect(_draw_people)
	share.add_child(_people)
	add_child(Palette.fold("Share of the electorate", share))
	if not movers.is_empty():
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		for m in movers.slice(0, 5):
			var button := Button.new()
			button.theme_type_variation = "Link"
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var measured: bool = m[3]
			var up := float(m[2]) > 0.0
			button.text = (("▲ %s: raising it wins them over" if up else "▼ %s: raising it loses them") % str(m[1])) if measured 				else "%s  (through the model's formulas)" % str(m[1])
			var target := str(m[0])
			button.pressed.connect(func() -> void: follow.emit(target))
			list.add_child(button)
		add_child(Palette.fold("Policies that matter most to them", list))
	var homes := VBoxContainer.new()
	homes.add_theme_constant_override("separation", 8)
	_homes_note = _muted("Finding some of their households…")
	# Stage S13.5: a group estimated from published shares has no households of its own.
	estimate = str(node.get("estimate", ""))
	if estimate != "":
		_homes_note.name = "estimate_note"
		_homes_note.text = "Who belongs to this group is an estimate, made from published shares (%s), not a fact recorded for any household. So it has no sample households to show." % estimate
	homes.add_child(_homes_note)
	_homes = GridContainer.new()
	_homes.name = "households"
	_homes.columns = 4
	_homes.add_theme_constant_override("h_separation", 12)
	_homes.add_theme_constant_override("v_separation", 12)
	homes.add_child(_homes)
	add_child(Palette.fold("Households", homes))


## The popup's width for this content.
func popup_width() -> float:
	return 640.0  # stage S14.1: one column, as every popup


func _muted(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.theme_type_variation = "Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	return label


## The approval, its change, the share and the drivers as they stand. `cells_of(name)` is
## the bridge's cells().
func refresh(value_of: Callable, before_of: Callable, cells_of: Callable, drivers: Array) -> void:
	var now: Variant = value_of.call(row)
	var was: Variant = before_of.call(row)
	var silent := now != null and absf(float(now)) < 0.0005 and _note != ""
	approval_text = "–" if silent or now == null else fmt.value(entry, now, true, false)
	_figure.text = approval_text
	_note_label.text = _note
	_note_label.visible = silent
	# Stage S13.6: before the first month has run there is no figure yet, and it says so.
	_change.text = "no change on last month" if now != null else "awaiting the first month's figures"
	_change.add_theme_color_override("font_color", Palette.MUTED)
	if not silent and now != null and was != null and fmt.change(entry, float(now) - float(was)) != "no change":
		var d := float(now) - float(was)
		_change.text = ("▲ " if d > 0.0 else "▼ ") + fmt.change(entry, d) + " on last month"
		_change.add_theme_color_override("font_color", Palette.GOOD if d > 0.0 else Palette.BAD)
	elif silent:
		_change.text = ""
	var share: Variant = value_of.call(share_row) if share_row != "" else null
	_share = float(share) if share != null else 0.0
	_share_label.text = "%s of adults: %d in every hundred." % [fmt.percent(_share), int(roundf(_share * 100.0))] if share != null \
		else "Awaiting the first month's figures."
	_people.queue_redraw()
	drivers_shown.clear()
	var values := []
	for d in drivers:
		var cells: Dictionary = cells_of.call(str(d[1]))
		var all: PackedFloat64Array = cells.get("values", PackedFloat64Array())
		values.append(all[index] if index >= 0 and index < all.size() else 0.0)
	var top := 0.05  # a pull smaller than this never fills a bar
	for v in values:
		top = maxf(top, absf(v))
	for i in values.size():
		var bar: Bar = _drivers.get_child(i * 3 + 1)
		# Stage S17.1: no bar beside "0.00", and a true minus sign.
		var nought: bool = absf(values[i]) < 0.005
		bar.fraction = 0.0 if nought else values[i] / top
		bar.queue_redraw()
		var amount: Label = _drivers.get_child(i * 3 + 2)
		amount.text = "–" if now == null else ("0.00" if nought else ("+" if values[i] > 0.0 else "−") + "%.2f" % absf(values[i]))
		drivers_shown.append([str(drivers[i][0]), float(values[i])])


## The approval's history, with the national rating (`national`, [row, label]) to compare.
func show_history(steps: PackedInt64Array, series_of: Callable, national: Array) -> void:
	chart.series = [{"row": row, "label": "Approval", "values": series_of.call(row), "color": Palette.BLUE}]
	if not national.is_empty():
		chart.series.append({"row": national[0], "label": str(national[1]), "values": series_of.call(str(national[0])), "color": Palette.BRICK, "removable": false})
	chart.set_data(steps, [])


## A hundred figures in four rows, the group's share of them in ink.
func _draw_people() -> void:
	var filled := int(roundf(_share * 100.0))
	var per_row := 25
	var cell := minf(_people.size.x / per_row, 24.0)
	for i in 100:
		var at := Vector2((i % per_row) * cell + cell / 2.0, (i / per_row) * 26.0 + 4.0)
		GroupCardWords.person(_people, at, cell * 0.3, Palette.INK if i < filled else Palette.RULE)


## The sample households, each as a tile; `house` is [play.web] household, `words` the
## labels of the region and household-type dimensions: {column: PackedStringArray}.
func show_households(found: Array, house: Dictionary, words: Dictionary) -> void:
	records = found
	for child in _homes.get_children():
		child.queue_free()
	_homes_note.text = "Eight of their households, chosen across the group. Open one for its year's account." if not found.is_empty() \
		else "No households found."
	for record in found:
		var tile := HouseholdTile.new()
		tile.fmt = fmt
		tile.set_record(record, house, words)
		tile.pressed.connect(func() -> void: household_opened.emit(record))
		_homes.add_child(tile)


## A household as a tile: a figure per adult and a smaller one per child, its region and
## kind in words, its net income a year with the change on a year before, and how likely
## its adults are to back the government.
class HouseholdTile extends Button:
	var fmt: RefCounted
	var adults := 1
	var children := 0
	var lines: Array = []  # [text, font, colour]
	var vote_note := ""

	func _init() -> void:
		custom_minimum_size = Vector2(120, 236)  # stage S13.5: room for the vote on two lines
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_record(record: Dictionary, house: Dictionary, words: Dictionary) -> void:
		adults = int(record.get(str(house.get("adults", "adults")), 1))
		children = int(record.get(str(house.get("children", "children")), 0))
		var place := GroupCardWords.word(record, str(house.get("region", "")), words)
		var kind := GroupCardWords.word(record, str(house.get("type", "")), words)
		var net: float = float(record.get(str(house.get("net_income", "")), 0.0)) * fmt.steps_per_year
		var change: Variant = record.get(str(house.get("change", "")))
		var support: Variant = record.get(str(house.get("support", "")))
		lines = [[place, Palette.text(600), Palette.INK], [kind, Palette.text(400), Palette.MUTED],
			[GroupCardWords.whole(fmt, net) + " a year", Palette.text(600), Palette.INK]]
		if change != null:
			# Stage S13.6: the change in its income, in words.
			var c := float(change)
			var by: String = fmt.percent(absf(c))
			var said := "income as a year ago" if fmt.is_nought(by) else "income %s %s on a year ago" % ["up" if c > 0.0 else "down", by]
			lines.append([said, Palette.text(400), Palette.MUTED if fmt.is_nought(by) else (Palette.GOOD if c > 0.0 else Palette.BAD)])
		if support != null:
			# Stage S13.5: the chance an adult here votes for the government, counting those who
			# would not vote, so it reads lower than the group's approval (of those who would).
			lines.append(["%s likely to vote for you" % fmt.percent(float(support), 0), Palette.text(400), Palette.MUTED])
			vote_note = "Each adult here has a %s chance of voting for you, counting those who would not vote at all; the group's approval counts only those who would." % fmt.percent(float(support), 0)
		tooltip_text = "%s, %s" % [kind, place] + ("\n" + vote_note if vote_note != "" else "")

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(box.position + Vector2(3, 3), box.size - Vector2(3, 3)), Palette.SHADOW)
		draw_rect(Rect2(box.position, box.size - Vector2(3, 3)), Palette.PAPER if not is_hovered() else Palette.CARD)
		draw_rect(Rect2(box.position, box.size - Vector2(3, 3)), Palette.INK, false, 2.0 if is_hovered() or has_focus() else 1.0)
		# The people: adults full height, children two thirds, standing on one line.
		var count := adults + children
		var step := minf(26.0, (size.x - 20.0) / maxf(count, 1))
		var x := (size.x - 3.0 - step * count) / 2.0 + step / 2.0
		for i in count:
			var s := 9.0 if i < adults else 6.0
			GroupCardWords.person(self, Vector2(x, 54.0 - s * 3.45), s, Palette.INK)
			x += step
		draw_line(Vector2(10, 56), Vector2(size.x - 13, 56), Palette.RULE, 1.0)
		var y := 76.0
		var room := size.x - 17.0
		for line in lines:
			var font: Font = line[1]
			# A line too long for the tile goes on two, cut between words.
			var parts := [str(line[0])]
			if font.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > room and parts[0].contains(" "):
				var words: PackedStringArray = str(parts[0]).split(" ")
				var cut: int = words.size() - 1
				while cut > 1 and font.get_string_size(" ".join(words.slice(0, cut)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > room:
					cut -= 1
				parts = [" ".join(words.slice(0, cut)), " ".join(words.slice(cut))]
			for part in parts:
				var px := 13
				while font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room and px > 12:
					px -= 1
				draw_string(font, Vector2(8, y), part, HORIZONTAL_ALIGNMENT_LEFT, room, px, line[2])
				y += 17.0
			y += 3.0


## Words for a household's data columns, and its pictogram.
class GroupCardWords:
	## A data column read in words through a dimension's labels: `spec` is "column:dim".
	static func word(record: Dictionary, spec: String, words: Dictionary) -> String:
		var column := spec.get_slice(":", 0)
		var labels: PackedStringArray = words.get(column, PackedStringArray())
		var code := int(record.get(column, -1))
		return labels[code] if code >= 0 and code < labels.size() else ""

	## An amount in minor units as whole pounds (or whatever the currency is): £9,894.
	static func whole(fmt: RefCounted, minor_units: float) -> String:
		var amount := minor_units / float(fmt.minor)
		return ("−" if amount < -0.5 else "") + fmt.with_symbol(fmt.grouped(roundf(absf(amount))))

	## A pictogram of a person about 3.5 times `s` tall, its head's top at `top`.
	static func person(canvas: CanvasItem, top: Vector2, s: float, colour: Color) -> void:
		canvas.draw_circle(top + Vector2(0, s * 0.75), s * 0.62, colour)
		var body := Rect2(top + Vector2(-s * 0.85, s * 1.55), Vector2(s * 1.7, s * 1.9))
		canvas.draw_rect(body, colour)
		canvas.draw_circle(body.position + Vector2(s * 0.85, 0), s * 0.85, colour)


## A household's account for the year: each line of `house.account` (a "-" in front is
## taken away), then its net income. `lines` and `net` are kept for tests.
class HouseholdAccount extends VBoxContainer:
	var lines: Array = []  # [label, signed amount in minor units a year]
	var net := 0.0

	func build(record: Dictionary, house: Dictionary, entries: Dictionary, fmt: RefCounted, words: Dictionary) -> void:
		add_theme_constant_override("separation", 12)
		add_child(Palette.caps("A household's year"))
		var title := Label.new()
		title.theme_type_variation = "Title"
		title.text = GroupCardWords.word(record, str(house.get("type", "")), words)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(title)
		var place := Label.new()
		place.theme_type_variation = "Muted"
		var adults := int(record.get(str(house.get("adults", "adults")), 1))
		var children := int(record.get(str(house.get("children", "children")), 0))
		place.text = "%s · %d %s%s" % [GroupCardWords.word(record, str(house.get("region", "")), words), adults,
			"adult" if adults == 1 else "adults", "" if children == 0 else ", %d %s" % [children, "child" if children == 1 else "children"]]
		add_child(place)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 8)
		Palette.rule_rows(grid)
		add_child(grid)
		var total := 0.0
		for spec in house.get("account", []):
			var name := str(spec).trim_prefix("-")
			var sign := -1.0 if str(spec).begins_with("-") else 1.0
			var amount := float(record.get(name, 0.0)) * sign
			total += amount
			var label := str(entries.get(name, {}).get("label", name))
			lines.append([label, amount])
			_line(grid, label, amount, fmt, false)
		var monthly := float(record.get(str(house.get("net_income", "")), 0.0))
		net = monthly * fmt.steps_per_year
		_line(grid, "Net income", net, fmt, true)
		var note := Label.new()
		note.theme_type_variation = "Muted"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(300, 0)
		note.text = "%s a month. Before housing costs; other income is not in the model." % fmt.money(monthly)
		add_child(note)

	func _line(grid: GridContainer, label: String, amount: float, fmt: RefCounted, strong: bool) -> void:
		var name := Label.new()
		name.text = label
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := Label.new()
		value.text = GroupCardWords.whole(fmt, amount)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(160, 0)
		if strong:
			for l in [name, value]:
				l.add_theme_font_override("font", Palette.display(500))
				l.add_theme_font_size_override("font_size", 22)
		grid.add_child(name)
		grid.add_child(value)
