extends PanelContainer
## Stage S12.3: the policy web. Three bands, left to right: the player's policies (by area,
## or the policies of one area), the outcomes the scenario's [play] names (headline, watch
## and "who gains" totals), and the situations and the government's support. A link means
## the policy reaches the outcome through some chain of the model's formulas that passes no
## other node on the web; "Why" shows the chain. Pointing at a node lights its links;
## pressing an area opens its policies, pressing anything else explains it.

const Palette := preload("res://scripts/palette.gd")
const NODE_H := 44.0
const GAP_Y := 8.0
const BAND_GAP := 64.0

signal explain_requested(name: String)

var fmt: RefCounted
var area := ""  # "" shows the policy areas; otherwise the policies of that area
var nodes := {}  # key -> {band, label, name (entry or ""), button}
var links: Array = []  # [from key, to key]
var _entries := {}
var _areas := {}  # area -> lever names
var _icons := {}
var _middle: PackedStringArray = []
var _right: PackedStringArray = []
var _reach := {}  # lever or outcome name -> displayed names it reaches first
var _lit := ""
var _canvas: Control
var _title: Label
var _back: Button
var _latest: Callable
var _previous: Callable


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_back = Button.new()
	_back.text = "‹ All policy areas"
	_back.theme_type_variation = "Link"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(func() -> void: open_area(""))
	box.add_child(_back)
	_title = Label.new()
	_title.text = "Policy web"
	_title.theme_type_variation = "Title"
	box.add_child(_title)
	var hint := Label.new()
	hint.text = "What each policy reaches. Point at anything to light its links; press a policy area to open it, anything else to see why it moved."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Palette.MUTED)
	hint.add_theme_font_size_override("font_size", Palette.SMALL)
	box.add_child(hint)
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", int(BAND_GAP))
	for text in ["Policies", "Outcomes", "Situations and support"]:
		var head := Label.new()
		head.text = text
		head.theme_type_variation = "Heading"
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heads.add_child(head)
	box.add_child(heads)
	_canvas = Control.new()
	_canvas.name = "web_canvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_links)
	_canvas.resized.connect(_place)
	box.add_child(_canvas)


## The catalogue (name -> entry), the scenario's [play] table and the player's levers.
func build(entries: Dictionary, play: Dictionary, levers: Array, icons: Dictionary) -> void:
	_entries = entries
	_icons = icons
	_areas.clear()
	for entry in levers:
		var group := str(entry.get("group", "")) if str(entry.get("group", "")) != "" else "Other"
		if not _areas.has(group):
			_areas[group] = []
		_areas[group].append(str(entry["name"]))
	var rows := {}  # row name -> entry name
	for name in entries:
		var row := str(entries[name].get("row", ""))
		if row != "":
			rows[row] = name
	_middle = PackedStringArray()
	var wanted: Array = Array(play.get("headline", [])) + Array(play.get("watch", []))
	wanted.append(play.get("breakdown_all", ""))
	wanted.append_array((play.get("breakdown_totals", {}) as Dictionary).values())
	var politics: Dictionary = play.get("politics", {})
	_right = PackedStringArray()
	for name in entries:
		if str(entries[name].get("situation", "")) != "":
			_right.append(name)
	for key in ["support", "turnout"]:
		var name := str(rows.get(str(politics.get(key, "")), politics.get(key, "")))
		if entries.has(name) and not _right.has(name):
			_right.append(name)
	for key in wanted:
		var name := str(rows.get(str(key).trim_prefix("-"), key))
		if entries.has(name) and not _middle.has(name) and not _right.has(name):
			_middle.append(name)
	_reach.clear()
	_consumer_cache.clear()
	if not _areas.has(area):
		area = ""
	open_area(area)


## Everything `start` reaches downstream, stopping at the first node shown on the web.
func reaches(start: String, shown: Dictionary) -> PackedStringArray:
	var consumers := _consumers()
	var out := PackedStringArray()
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var name: String = queue.pop_front()
		for next in consumers.get(name, []):
			if seen.has(next):
				continue
			seen[next] = true
			if shown.has(next):
				out.append(next)
			else:
				queue.append(next)
	return out


var _consumer_cache := {}


func _consumers() -> Dictionary:
	if not _consumer_cache.is_empty():
		return _consumer_cache
	for name in _entries:
		var entry: Dictionary = _entries[name]
		for list in [entry.get("inputs", PackedStringArray()), entry.get("lagged_inputs", PackedStringArray())]:
			for used in list:
				if not _consumer_cache.has(used):
					_consumer_cache[used] = []
				if not (_consumer_cache[used] as Array).has(name):
					_consumer_cache[used].append(name)
	return _consumer_cache


## Shows the policy areas (""), or the policies of one area, and works out the links.
func open_area(name: String) -> void:
	area = name
	_back.visible = area != ""
	_title.text = "Policy web" if area == "" else "Policy web: " + area
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	nodes.clear()
	links.clear()
	_lit = ""
	var shown := {}
	for n in _middle:
		shown[n] = true
	for n in _right:
		shown[n] = true
	if area == "":
		for group in _areas:
			_add_node("area:" + group, 0, group, "", _icons.get(group))
			var hit := {}
			for lever in _areas[group]:
				for target in _cached_reach(lever, shown):
					hit[target] = true
			for target in hit:
				links.append(["area:" + group, target])
	else:
		for lever in _areas[area]:
			_add_node(lever, 0, _label(lever), lever, null)
			for target in _cached_reach(lever, shown):
				links.append([lever, target])
	for n in _middle:
		_add_node(n, 1, _label(n), n, null)
		for target in _cached_reach(n, shown):
			if _right.has(target):
				links.append([n, target])
	for n in _right:
		_add_node(n, 2, _label(n), n, null)
	_place()
	refresh(_latest, _previous)


func _cached_reach(name: String, shown: Dictionary) -> PackedStringArray:
	if not _reach.has(name):
		_reach[name] = reaches(name, shown)
	return _reach[name]


func _label(name: String) -> String:
	var label := str(_entries.get(name, {}).get("label", ""))
	return label if label != "" else name.replace("_", " ")


func _add_node(key: String, band: int, label: String, name: String, icon: Variant) -> void:
	var button := Button.new()
	button.name = "node_" + key.replace(":", "_").replace(" ", "_")
	button.theme_type_variation = "WebNode"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text = label
	button.tooltip_text = str(_entries.get(name, {}).get("doc", ""))
	if icon != null:
		button.icon = icon
	button.mouse_entered.connect(func() -> void: _light(key))
	button.mouse_exited.connect(func() -> void: _light(""))
	if key.begins_with("area:"):
		button.pressed.connect(func() -> void: open_area(key.substr(5)))
	else:
		button.pressed.connect(func() -> void: explain_requested.emit(name))
	_canvas.add_child(button)
	nodes[key] = {"band": band, "label": label, "name": name, "button": button}


## Lays the nodes out in their bands; the canvas is as tall as the longest band.
func _place() -> void:
	if _canvas == null:
		return
	var width := (_canvas.size.x - 2.0 * BAND_GAP) / 3.0
	var counts := [0, 0, 0]
	for key in nodes:
		var node: Dictionary = nodes[key]
		var b: int = node["band"]
		var button: Button = node["button"]
		button.position = Vector2(b * (width + BAND_GAP), counts[b] * (NODE_H + GAP_Y))
		button.size = Vector2(maxf(width, 60.0), NODE_H)
		counts[b] += 1
	_canvas.custom_minimum_size = Vector2(0, counts.max() * (NODE_H + GAP_Y))
	_canvas.queue_redraw()


func _light(key: String) -> void:
	_lit = key
	_canvas.queue_redraw()


func is_linked(a: String, b: String) -> bool:
	return links.any(func(l): return (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a))


func _draw_links() -> void:
	for link in links:
		if not nodes.has(link[0]) or not nodes.has(link[1]):
			continue
		var from: Button = nodes[link[0]]["button"]
		var to: Button = nodes[link[1]]["button"]
		var lit: bool = _lit != "" and (link[0] == _lit or link[1] == _lit)
		var colour := Palette.ACCENT if lit else (Color(Palette.LINE, 0.45) if _lit == "" else Color(Palette.RULE, 0.3))
		var a := from.position + Vector2(from.size.x, NODE_H / 2.0)
		var b := to.position + Vector2(0, NODE_H / 2.0)
		var bend := (b.x - a.x) * 0.5
		var points := PackedVector2Array()
		for i in 17:
			var t := i / 16.0
			var u := 1.0 - t
			points.append(u * u * u * a + 3.0 * u * u * t * (a + Vector2(bend, 0)) + 3.0 * u * t * t * (b - Vector2(bend, 0)) + t * t * t * b)
		_canvas.draw_polyline(points, colour, 2.0 if lit else 1.0, true)


## Each outcome's value and last month's change; each situation, whether it is on now.
func refresh(latest: Callable, previous: Callable) -> void:
	_latest = latest
	_previous = previous
	if not latest.is_valid():
		return
	for key in nodes:
		var node: Dictionary = nodes[key]
		var name: String = node["name"]
		if name == "" or nodes[key]["band"] == 0:
			continue
		var entry: Dictionary = _entries.get(name, {})
		var row := str(entry.get("row", ""))
		var button: Button = node["button"]
		if row == "":
			continue
		var now: Variant = latest.call(row)
		if str(entry.get("situation", "")) != "":
			var on: bool = now == true
			button.text = ("● " if on else "○ ") + node["label"]
			var colour := (Palette.GOOD if str(entry["situation"]) == "good" else Palette.BAD) if on else Palette.MUTED
			for state in ["font_color", "font_hover_color", "font_focus_color"]:
				button.add_theme_color_override(state, colour)
			continue
		var text: String = node["label"]
		if now != null and typeof(now) != TYPE_BOOL:
			text += "\n" + fmt.value(entry, now, true, false)
		button.text = text
