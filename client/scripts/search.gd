extends LineEdit
## Stage S15.1: search, on the top bar. Typing finds policies in force, statistics, groups,
## situations and policies not in force by their label, the model's own name and doc, and any
## other words the scenario gives (`also`), from an index built once per model, so a key costs
## no engine call. A small list under the field shows the matches by kind; the arrows move,
## Enter opens the one chosen, Esc clears and leaves. The screen (main.gd) dims the board to
## the matches and lights the chosen one's node.

const Palette := preload("res://scripts/palette.gd")

## The query changed: the matches, best first, each {key, kind, label, icon, node}.
signal searched(found: Array)
## A match was chosen (Enter or a click), or pointed at / selected (to light its node).
signal picked(result: Dictionary)
signal pointed(result: Dictionary)

## Stage S17.1: the field's width with room to type in (on a wide bar, on a narrow one) and
## as its button, the magnifier alone.
const WIDE := 190.0
const NARROW := 150.0
const BUTTON := 40.0

const KINDS := {"policy": "Policies", "statistic": "Statistics", "group": "Groups", "situation": "Situations", "add": "Not in force: add",
	"shelf": "Not on the board"}
const SHOWN := 10

## Every thing to find: {key, kind, label, icon, node, words: [label, also, name, doc] lowercased}.
var index: Array = []
var found: Array = []
var chosen := 0
## The list under the field (added to the screen by main.gd, over the board).
var results: PanelContainer
var _rows: VBoxContainer
var _buttons: Array = []
## Stage S17.1: `narrow` the bar is short of room; `compact` it has asked the field to be its
## button, which it is except while it holds the keyboard or any words.
var narrow := false
var compact := false
## The field opened or shut as a button: the bar fits itself again.
signal fitted


func _ready() -> void:
	name = "search"
	placeholder_text = "Search   /"
	custom_minimum_size = Vector2(WIDE, 0)
	clear_button_enabled = true
	right_icon = _magnifier()
	focus_entered.connect(_fit)
	focus_exited.connect(_fit)
	add_theme_color_override("font_placeholder_color", Color(Palette.INK, 0.7))  # stage S17.1: 4.5 to 1 on the field
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tooltip_text = "Find a policy, a statistic, a group or a situation (/ or Ctrl+F)"
	results = PanelContainer.new()
	results.name = "search_results"
	results.add_theme_stylebox_override("panel", Palette.card(8, 5, 2))
	results.visible = false
	results.mouse_filter = Control.MOUSE_FILTER_STOP
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	results.add_child(_rows)
	text_changed.connect(_query)
	text_submitted.connect(func(_t: String) -> void: open_chosen())
	focus_exited.connect(func() -> void:
		# A click on a result moves the focus first: the list stays a moment for the click.
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if not has_focus() and text == "":
				results.visible = false))


## The index: `items` as above, the words lowercased once here.
func set_index(items: Array) -> void:
	index = items
	for item in index:
		var words: Array = item["words"]
		item["words"] = words.map(func(w): return str(w).to_lower())
	if text != "":
		_query(text)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_DOWN:
			_choose(chosen + 1)
			accept_event()
		KEY_UP:
			_choose(chosen - 1)
			accept_event()
		KEY_ESCAPE:
			clear_search()
			release_focus()
			accept_event()


func clear_search() -> void:
	text = ""
	_query("")
	_fit()


## Stage S17.1: true while the field is its button only.
func is_button() -> bool:
	return compact and not has_focus() and text == ""


## Stage S17.1: `on` asks the field to be its button (the top bar, short of room); `tight` for
## the narrower of its two widths when open.
func set_compact(on: bool, tight: bool) -> void:
	compact = on
	narrow = tight
	_fit(false)


func _fit(tell := true) -> void:
	var button := is_button()
	var wide := BUTTON if button else (NARROW if narrow else WIDE)
	placeholder_text = "" if button else "Search   /"
	clear_button_enabled = not button
	# A field keeps room for four characters; its button needs none.
	if button:
		add_theme_constant_override("minimum_character_width", 0)
	else:
		remove_theme_constant_override("minimum_character_width")
	if custom_minimum_size.x != wide:
		custom_minimum_size.x = wide
		if tell:
			fitted.emit()


## A magnifying glass, drawn in ink: the search's own mark, all that shows of it as a button.
static func _magnifier() -> Texture2D:
	var size := 18
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var centre := Vector2(7.5, 7.5)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(centre)
			var along := (p - Vector2(11.5, 11.5)).dot(Vector2(1, 1).normalized())
			var across := absf((p - Vector2(11.5, 11.5)).dot(Vector2(1, -1).normalized()))
			if (d >= 4.0 and d <= 6.0) or (along >= 0.0 and along <= 7.5 and across <= 1.2):
				image.set_pixel(x, y, Palette.INK)
	return ImageTexture.create_from_image(image)


## For the checks and the keys: as if typed.
func type_query(words: String) -> void:
	text = words
	_query(words)


func open_chosen() -> void:
	if chosen >= 0 and chosen < found.size():
		var result: Dictionary = found[chosen]
		picked.emit(result)


## Matches for a query: every word of it found in a thing's label, other words, name or doc;
## ranked by where the words were found (the label first), then by kind.
func find(query: String) -> Array:
	var terms := query.to_lower().strip_edges().split(" ", false)
	if terms.is_empty():
		return []
	var scored := []
	for item in index:
		var words: Array = item["words"]
		var worst := 0
		var ok := true
		for t in terms:
			var best := -1
			for i in words.size():
				if str(words[i]).contains(t):
					best = i
					break
			if best < 0:
				ok = false
				break
			worst = maxi(worst, best)
		if ok:
			var starts := 0 if str(words[0]).begins_with(terms[0]) else 1
			scored.append([worst * 2 + starts, KINDS.keys().find(item["kind"]), item])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return scored.map(func(s): return s[2])


func _query(words: String) -> void:
	_fit()
	found = find(words)
	chosen = 0
	_fill()
	searched.emit(found)
	if not found.is_empty():
		pointed.emit(found[0])


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	results.visible = text.strip_edges() != ""
	if not results.visible:
		return
	if found.is_empty():
		var none := Label.new()
		none.text = "Nothing called that."
		none.theme_type_variation = "Muted"
		_rows.add_child(none)
	# The matches shown, grouped by kind in the order they rank.
	var shown: Array = found.slice(0, SHOWN)
	var kinds: Array = []
	for item in shown:
		if not kinds.has(item["kind"]):
			kinds.append(item["kind"])
	var order: Array = []
	for kind in kinds:
		_rows.add_child(Palette.caps(KINDS[kind]))
		for item in shown:
			if item["kind"] == kind:
				order.append(item)
				_rows.add_child(_row(item, found.find(item)))
	# The list's order is the arrows' order.
	var rest: Array = found.slice(SHOWN)
	found = order + rest
	if found.size() > SHOWN:
		var more := Label.new()
		more.text = "and %d more on the board" % (found.size() - SHOWN)
		more.theme_type_variation = "Muted"
		_rows.add_child(more)
	_mark()
	results.reset_size()


func _row(item: Dictionary, _at: int) -> Button:
	var button := Button.new()
	button.theme_type_variation = "ReportLine"
	button.text = str(item["label"])
	button.icon = Palette.sized(item["icon"], 20)
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 20)
	button.add_theme_color_override("icon_normal_color", Palette.INK)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = 280
	button.focus_mode = Control.FOCUS_NONE
	# Chosen by the pointer only when it moves over a row (a list drawn under a resting pointer
	# must not move the choice away from the best match).
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and found.find(item) != chosen:
			_choose(found.find(item)))
	button.pressed.connect(func() -> void: picked.emit(item))
	_buttons.append([button, item])
	return button


func _choose(i: int) -> void:
	if found.is_empty():
		return
	chosen = clampi(i, 0, mini(found.size(), SHOWN) - 1)
	_mark()
	pointed.emit(found[chosen])


func _mark() -> void:
	for pair in _buttons:
		var on: bool = found.find(pair[1]) == chosen
		(pair[0] as Button).add_theme_stylebox_override("normal", Palette.chosen_row(8, 4) if on else Palette._empty(8, 4))
