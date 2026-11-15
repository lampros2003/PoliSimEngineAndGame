extends Control
## Stage S13.2: the board, the game's one screen. A cause-and-effect graph laid out as an
## ellipse that reads inward from cause to people: the player's policies on the outer ring
## in arcs by area (the area names set along the rim), the indicators on the middle ring in
## their area's sector, interest groups round the centre, and at the centre the government's
## approval, the months to the election and its political capital.
##
## The layout is authored, from the scenario's `[play.web]` (or, for a scenario without
## one, made from the levers' groups and the headline and watch rows), and placed by rule,
## so it never shifts between visits. Shape says the kind of node, size its importance
## (three tiers). Links appear only for the node under the pointer or the one selected.
## Nodes, links and effects are separate canvas items, so a hover redraws only what moved.
##
## Stage S13.4: the interest groups take a band of their own round a smaller centre, in
## families, sized by their share of the electorate, with approval as a gauge and a figure;
## every node is labelled at rest where its label has room; a policy's links are its
## strongest effects on indicators and on groups, each weighed against the target's own
## scale (what a typical policy does to it), and always the budget balance when it moves it; situation flags stand in the
## window's corners.

const Palette := preload("res://scripts/palette.gd")

signal node_pressed(key: String)
signal hover_changed(key: String)

## Node radius by tier, in pixels at a unit scale of 1.
const RADIUS := [0.0, 17.0, 22.0, 29.0]
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.0
## Links shown for a policy: the strongest few, above a small threshold.
const MAX_LINKS := 7
const LINK_FLOOR := 0.0005
## Stage S13.4: a policy's links to groups, besides its links to indicators.
const MAX_GROUP_LINKS := 3
## The groups' ring, as a fraction of the way from the centre medallion to the indicators'.
const GROUP_RING := Vector2(0.46, 0.4)
## The gap between two families of groups, in the same terms as a group's room.
const FAMILY_GAP := 26.0
## The largest group's radius, in pixels at a unit scale of 1.
const GROUP_MAX := 25.0
## Stage S13.5: the room the month's report takes at the right while it is open.
const DOCK_WIDTH := 412.0

var fmt: RefCounted
## key -> node: {key, kind ("policy", "indicator", "group", "flag", "centre"), label, icon,
## tier, area, levers, row, name (catalogue entry), better, doc, pos, r, label_rect, ...}
var nodes := {}
var order: PackedStringArray = []  # node keys in drawing order
var areas: Array = []  # {name, icon, policies: [key], indicators: [key], from, to (polar angles)}
var hidden_levers: PackedStringArray = []  # levers the board leaves out
var groups: Array = []  # [play.web] groups
## Stage S13.5: policies not in force (their lever at its `off` setting, no bill waiting to
## bring them in): key -> node, kept off the board and offered by their area's "introduce"
## node. A policy whose bill to introduce waits is on the board as a ghost.
var available := {}
var _appear := {}  # key -> 0..1, a policy just come into force growing onto the board
## Measured effects a year on, from the bridge: lever -> {row: signed strength}.
var effects := {}
## Stage S13.4: the row a policy always links to when it moves it ([play.web] `balance`).
var budget_row := "budget_balance"
var _scales := {}  # row -> the most any lever moves it in the effects table
## True when the board came from [play.web]; false for an automatic one.
var authored := false
var centre := {}  # approval, months, capital texts for the centre medallion
var hover := ""
var selected := ""
var zoom := 1.0
var pan := Vector2.ZERO
## While a popup or sheet is open the board takes no input.
var input_enabled := true

var _entries := {}
var _consumers := {}
var _reach := {}
var _unit := 1.0
## Stage S13.6: smaller nodes on a crowded board: the rim's and the groups' own factors.
var _node_scale := 1.0
var _group_scale := 1.0
var _c := Vector2.ZERO
var _rim: Array = []  # [glyph, position, angle, rect] for the area names along the rim
var _arcs: Array = []  # per area, the rim arc's points (in two pieces, either side of its name)
var _arc_ends: Array = []  # for each piece, the end of the area's arc it holds: 0 the start, 1 the end
var _guides: Array = []  # the rings' outlines, as points
var _group_ring: Ring  # stage S13.4: the groups' ring, or null
var _spokes: Array = []  # [rim point, middle-ring point] at each boundary between areas
var _links: Array = []  # {from, to, sign, strength, measured, points}
var _link_key := ""
var _draw_in := 1.0
var _flow := 0.0
var _dim := 0.0
var _lift := {}  # key -> 0..1
var _lift_tweens := {}
var _pulses := {}  # key -> seconds since the pulse began
var _flags: Array = []
var _press := Vector2.ZERO
var _dragging := false
var _pressing := false
var _tween_links: Tween
var _tween_dim: Tween
## Stage S13.6: how many times the set of links shown has been replaced (for the checks:
## a link set held steady under the pointer), the links' fade when measured ones replace
## those from the formulas, and the short grace before a hover ends.
var link_sets := 0
var _link_fade := 1.0
var _leave: Timer
const LEAVE_GRACE := 0.15
var _base: Control
var _link_layer: Control
var _node_layer: Control
var _fx_layer: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for layer in ["base", "links", "nodes", "effects"]:
		var c := Control.new()
		c.name = layer
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(c)
	_base = get_node("base")
	_link_layer = get_node("links")
	_node_layer = get_node("nodes")
	_fx_layer = get_node("effects")
	_base.draw.connect(_draw_base)
	_link_layer.draw.connect(_draw_links)
	_node_layer.draw.connect(_draw_nodes)
	_fx_layer.draw.connect(_draw_effects)
	# Stage S13.5: a change of size (the month's report docking) glides the nodes to their
	# new places.
	resized.connect(func() -> void:
		if nodes.has("centre") and nodes["centre"]["pos"] != Vector2.ZERO:
			_relayout_smoothly()
		else:
			layout())
	_leave = Timer.new()
	_leave.one_shot = true
	_leave.timeout.connect(func() -> void: set_hover(""))
	add_child(_leave)


# ---------------------------------------------------------------------------- building

## Builds the board from the catalogue (name -> entry), the scenario's [play] table and the
## player's levers. `label_of` gives a result row's label as the screen shows it. Stage
## S13.5: `lever_of` and `pending` (as for refresh) decide which policies are in force.
func build(entries: Dictionary, play: Dictionary, levers: Array, label_of: Callable, lever_of := Callable(), pending := {}) -> void:
	_entries = entries
	_consumers.clear()
	_reach.clear()
	for name in entries:
		var entry: Dictionary = entries[name]
		for list in [entry.get("inputs", PackedStringArray()), entry.get("lagged_inputs", PackedStringArray())]:
			for used in list:
				if not _consumers.has(used):
					_consumers[used] = PackedStringArray()
				if not (_consumers[used] as PackedStringArray).has(name):
					_consumers[used].append(name)
	nodes.clear()
	available.clear()
	_appear.clear()
	areas.clear()
	effects.clear()
	_links.clear()
	_link_key = ""
	var rows := {}
	for name in entries:
		var row := str(entries[name].get("row", ""))
		if row != "":
			rows[row] = name
	var web: Dictionary = play.get("web", {})
	authored = not web.is_empty()
	hidden_levers = PackedStringArray(web.get("hide", []))
	groups = web.get("groups", [])
	budget_row = str(web.get("balance", "budget_balance"))
	var player := {}
	for entry in levers:
		player[str(entry["name"])] = entry
	if authored:
		for area in web.get("areas", []):
			var a := {"name": str(area.get("name", "")), "icon": str(area.get("icon", "")), "policies": [], "indicators": []}
			for p in area.get("policies", []):
				var own := PackedStringArray()
				for lever in p.get("levers", []):
					if player.has(str(lever)) and not hidden_levers.has(str(lever)):
						own.append(str(lever))
				if own.is_empty():
					continue
				var key := "policy:" + str(p.get("key", own[0]))
				_add(key, "policy", str(p.get("label", entries[own[0]].get("label", own[0]))), str(p.get("icon", "")),
					int(p.get("size", 2)), a["name"], own, "", own[0])
				a["policies"].append(key)
				# Stage S13.5: how its first lever reads (levels, a unit, what an amount is for),
				# written into the catalogue entry so every screen says it the same way; and the
				# setting at which it is not in force, held as the engine stores it.
				_describe(entries.get(own[0], {}), p)
				nodes[key]["line"] = str(p.get("line", ""))
				if p.has("off") and own.size() == 1:
					var off := float(p["off"])
					nodes[key]["off"] = off
					nodes[key]["off_stored"] = off * (fmt.minor if fmt != null and entries[own[0]].get("money", false) else 1)
			for i in area.get("indicators", []):
				var row := str(i.get("row", ""))
				if not rows.has(row.trim_prefix("-")):
					continue
				_describe(entries.get(rows[row.trim_prefix("-")], {}), i)
				var key := "indicator:" + row
				_add(key, "indicator", label_of.call(row), str(i.get("icon", "")), int(i.get("size", 2)), a["name"],
					PackedStringArray(), row, rows[row.trim_prefix("-")], str(i.get("better", "")))
				a["indicators"].append(key)
			a["all"] = a["policies"].duplicate()
			if not a["policies"].is_empty() or not a["indicators"].is_empty():
				areas.append(a)
		# A lever the table does not place (a mod's, say) gets a policy of its own, in the
		# area of its group's name, or a new area of that name.
		var placed := {}
		for key in nodes:
			for lever in nodes[key]["levers"]:
				placed[lever] = true
		for entry in levers:
			var lever := str(entry["name"])
			if placed.has(lever) or hidden_levers.has(lever):
				continue
			var group := str(entry.get("group", "")) if str(entry.get("group", "")) != "" else "Other"
			var home: Dictionary = {}
			for a in areas:
				if a["name"] == group:
					home = a
			if home.is_empty():
				home = {"name": group, "icon": "", "policies": [], "indicators": [], "all": []}
				areas.append(home)
			var key := "policy:" + lever
			_add(key, "policy", str(entry.get("label", lever)), "", 2, group, PackedStringArray([lever]), "", lever)
			home["policies"].append(key)
			home["all"].append(key)
	else:
		_automatic(entries, play, levers, rows, label_of)
	for g in groups:
		var row := str(g.get("row", ""))
		if not rows.has(row):
			continue
		var key := "group:" + str(g.get("key", row))
		_add(key, "group", str(g.get("label", row)), str(g.get("icon", "group")), 2, "", PackedStringArray(), row, rows[row], "high")
		# Stage S13.4: its family on the board, its share of the electorate (which sizes it),
		# the flag that picks its households, and what to say for an approval of nought.
		for field in ["share", "family", "households", "note", "estimate"]:
			nodes[key][field] = str(g.get(field, ""))
		nodes[key]["share_value"] = -1.0
	_add("centre", "centre", "Government", "vote", 3, "", PackedStringArray(), "", "", "")
	selected = ""
	hover = ""
	if lever_of.is_valid():
		_sync(lever_of, pending)
	layout()


## Stage S13.5: copies a [play.web] item's description of its value into a catalogue entry.
static func _describe(entry: Dictionary, item: Dictionary) -> void:
	if entry.is_empty():
		return
	if item.has("levels"):
		entry["levels"] = Array(item["levels"]).map(func(l): return str(l))
	if item.has("unit"):
		entry["show_as"] = str(item["unit"])
	if item.has("per"):
		entry["per"] = str(item["per"])


## Stage S13.5: the policy nodes, on the board or not.
func policy_node(key: String) -> Dictionary:
	return nodes.get(key, available.get(key, {}))


## The policy that holds a lever, on the board or not, or "".
func holds(lever: String) -> String:
	var key := policy_of(lever)
	if key != "":
		return key
	for k in available:
		if (available[k]["levers"] as PackedStringArray).has(lever):
			return k
	return ""


## True when a stored lever value is a policy's `off` setting.
static func is_off(n: Dictionary, v: Variant) -> bool:
	return n.has("off_stored") and v != null and absf(float(v) - float(n["off_stored"])) <= 1e-6 * maxf(1.0, absf(float(n["off_stored"])))


## The policies of an area not in force, in the scenario's order.
func available_in(area: String) -> PackedStringArray:
	var out := PackedStringArray()
	for a in areas:
		if a["name"] == area:
			for key in a["all"]:
				if available.has(key):
					out.append(key)
	return out


## Stage S13.5: puts each policy on the board or off it: in force (its lever off its `off`
## setting), a ghost (a bill to introduce it waiting) or available to introduce; each area
## with policies to introduce gets its "introduce" node at the end of its arc. A ghost that
## comes into force grows onto the board. True when the board changed.
func _sync(lever_of: Callable, pending: Dictionary) -> bool:
	var changed := false
	for a in areas:
		if not a.has("all"):
			continue  # an automatic board's area: every policy always in force
		var present := []
		var spare := []
		for key in a["all"]:
			var n := policy_node(key)
			var lever: String = n["levers"][0]
			var in_force := not is_off(n, lever_of.call(lever))
			var ghost := not in_force and pending.has(lever) and not is_off(n, pending[lever])
			if in_force and n.get("ghost", false) and nodes.has(key):
				_appear[key] = 0.0  # its bill passed
			n["ghost"] = ghost
			if in_force or ghost:
				present.append(key)
				if available.has(key):
					nodes[key] = available[key]
					available.erase(key)
					changed = true
			else:
				spare.append(key)
				if nodes.has(key):
					available[key] = nodes[key]
					nodes.erase(key)
					changed = true
		var intro := "introduce:" + str(a["name"])
		if spare.is_empty():
			if nodes.has(intro):
				nodes.erase(intro)
				changed = true
		else:
			if not nodes.has(intro):
				_add(intro, "introduce", "New policy", "", 1, a["name"], PackedStringArray(), "", "")
				changed = true
			nodes[intro]["count"] = spare.size()
			present.append(intro)
		a["policies"] = present
	if changed:
		for key in [hover, selected, _link_key]:
			if key != "" and not nodes.has(key):
				hover = "" if hover == key else hover
				selected = "" if selected == key else selected
		_links = []
		_link_key = ""
		_order_nodes()
	for key in _appear.keys():
		if _appear[key] == 0.0 and nodes.has(key):
			_pulses[key] = 0.0
			if DisplayServer.get_name() == "headless":
				_appear.erase(key)
				continue
			var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_method(func(k: float) -> void:
				_appear[key] = k
				_node_layer.queue_redraw(), 0.001, 1.0, 0.6)
			tween.tween_callback(func() -> void: _appear.erase(key))
	return changed


## A board for a scenario without [play.web]: an area per lever group (in the order the
## model names them), one policy per lever, and the headline and watch rows as indicators,
## each in the sector of the area whose levers reach it, or the emptiest.
func _automatic(entries: Dictionary, play: Dictionary, levers: Array, rows: Dictionary, label_of: Callable) -> void:
	var by_name := {}
	for entry in levers:
		var group := str(entry.get("group", "")) if str(entry.get("group", "")) != "" else "Policy"
		if not by_name.has(group):
			by_name[group] = {"name": group, "icon": "", "policies": [], "indicators": []}
			areas.append(by_name[group])
		var key := "policy:" + str(entry["name"])
		# A small board labels every policy; a large one only on hover and zoom.
		_add(key, "policy", str(entry.get("label", entry["name"])), "", 3 if levers.size() <= 12 else 2, group, PackedStringArray([entry["name"]]), "", str(entry["name"]))
		by_name[group]["policies"].append(key)
	var headline: Array = play.get("headline", [])
	var keys: Array = []
	for k in headline + Array(play.get("watch", [])):
		if not keys.has(str(k)) and rows.has(str(k).trim_prefix("-")):
			keys.append(str(k))
	var shown := {}
	for k in keys:
		shown[rows[k.trim_prefix("-")]] = true
	for k in keys:
		var name: String = rows[k.trim_prefix("-")]
		var home: Dictionary = {}
		for a in areas:
			for p in a["policies"]:
				if reaches(nodes[p]["levers"][0], shown).has(name):
					home = a
					break
			if not home.is_empty():
				break
		if home.is_empty() and not areas.is_empty():
			home = areas[0]
			for a in areas:
				if a["indicators"].size() < home["indicators"].size():
					home = a
		if home.is_empty():
			home = {"name": "", "icon": "", "policies": [], "indicators": []}
			areas.append(home)
		var key: String = "indicator:" + k
		_add(key, "indicator", label_of.call(k), "", 3 if headline.has(k) else 2, home["name"], PackedStringArray(), k, name)
		home["indicators"].append(key)


func _add(key: String, kind: String, label: String, icon: String, tier: int, area: String, levers: PackedStringArray,
		row: String, name: String, better := "") -> void:
	var entry: Dictionary = _entries.get(name, {})
	var fallback := {"policy": "policy", "indicator": "indicator", "group": "group", "centre": "vote", "flag": "indicator"}
	nodes[key] = {"key": key, "kind": kind, "label": label, "tier": clampi(tier, 1, 3), "area": area, "levers": levers,
		"row": row, "name": name, "better": better, "doc": str(entry.get("doc", "")),
		"icon": Palette.icon(icon if icon != "" else fallback.get(kind, "policy")), "pos": Vector2.ZERO, "r": 10.0,
		"label_rect": Rect2(), "fraction": -1.0, "pending": -1.0, "trend": 0, "value": "", "change": ""}


## Everything `start` reaches downstream through the formulas' inputs, stopping at the
## first node in `shown` on each path (the S12 reach search).
func reaches(start: String, shown: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var name: String = queue.pop_front()
		for next in _consumers.get(name, PackedStringArray()):
			if seen.has(next):
				continue
			seen[next] = true
			if shown.has(next):
				out.append(next)
			else:
				queue.append(next)
	return out


## What a value's formula reads (data columns and parameters left out: they never change).
func inputs_of(name: String) -> PackedStringArray:
	var entry: Dictionary = _entries.get(name, {})
	var out := PackedStringArray()
	for list in [entry.get("inputs", PackedStringArray()), entry.get("lagged_inputs", PackedStringArray())]:
		for used in list:
			if _entries.has(used) and not out.has(used) and not str(_entries[used].get("kind", "")) in ["column", "param"]:
				out.append(used)
	return out


## What reads a value.
func consumers_of(name: String) -> PackedStringArray:
	return _consumers.get(name, PackedStringArray())


func keys_of(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for key in order:
		if nodes[key]["kind"] == kind:
			out.append(key)
	return out


## The policy node that holds a lever, or "".
func policy_of(lever: String) -> String:
	for key in nodes:
		if nodes[key]["kind"] == "policy" and (nodes[key]["levers"] as PackedStringArray).has(lever):
			return key
	return ""


# ---------------------------------------------------------------------------- layout

## A ring: an ellipse sampled by arc length, read by polar angle round the centre.
class Ring:
	var rx := 1.0
	var ry := 1.0
	var c := Vector2.ZERO
	var s := PackedFloat64Array()  # cumulative length, normalised to 1
	var phi := PackedFloat64Array()  # polar angle from the top, clockwise, 0..TAU
	var t := PackedFloat64Array()
	const N := 720

	func _init(centre: Vector2, a: float, b: float) -> void:
		c = centre
		rx = maxf(a, 1.0)
		ry = maxf(b, 1.0)
		var total := 0.0
		var last := Vector2.ZERO
		for i in N + 1:
			var u := -PI / 2.0 + TAU * float(i) / N
			var p := Vector2(rx * cos(u), ry * sin(u))
			if i > 0:
				total += p.distance_to(last)
			last = p
			s.append(total)
			t.append(u)
			phi.append(fposmod(atan2(p.y, p.x) + PI / 2.0, TAU) if i < N else TAU)
		for i in s.size():
			s[i] /= total
		phi[0] = 0.0

	func length() -> float:
		return PI * (3.0 * (rx + ry) - sqrt((3.0 * rx + ry) * (rx + 3.0 * ry)))

	## The point at a fraction of the way round, from the top, clockwise.
	func at(f: float) -> Vector2:
		f = fposmod(f, 1.0)
		var i := s.bsearch(f)
		i = clampi(i, 1, N)
		var k := (f - s[i - 1]) / maxf(s[i] - s[i - 1], 1e-12)
		var u := lerpf(t[i - 1], t[i], k)
		return c + Vector2(rx * cos(u), ry * sin(u))

	## The fraction of the way round at a polar angle from the top, clockwise.
	func fraction(angle: float) -> float:
		angle = fposmod(angle, TAU)
		var i := clampi(phi.bsearch(angle), 1, N)
		var k := (angle - phi[i - 1]) / maxf(phi[i] - phi[i - 1], 1e-12)
		return lerpf(s[i - 1], s[i], k)

	## The polar angle of a fraction of the way round.
	func angle(f: float) -> float:
		var p := at(f) - c
		return fposmod(atan2(p.y, p.x) + PI / 2.0, TAU)


## Places every node for the board's current size. The board is laid out to fill the
## window at zoom 1; pan and zoom move the view, never the layout.
func layout() -> void:
	if nodes.is_empty() or size.x < 10.0 or size.y < 10.0:
		return
	_unit = clampf(minf(size.x / 1.55, size.y) / 800.0, 0.72, 2.2)
	var u := _unit
	_c = size / 2.0 + Vector2(0, 6.0 * u)
	var rim_room := 34.0 * u  # the area names outside the policies
	var outer := Ring.new(_c, size.x / 2.0 - rim_room - RADIUS[3] * u - 14.0 * u, size.y / 2.0 - rim_room - RADIUS[3] * u - 6.0 * u)
	var gap := (RADIUS[3] * 2.0 + 44.0) * u  # between the policy ring and the indicator ring
	var middle := Ring.new(_c, outer.rx - gap * 1.1, outer.ry - gap)
	# Stage S13.4: a closer back row when groups need the room inside it.
	var stagger := (RADIUS[3] * (2.0 if keys_of_unordered("group").is_empty() else 1.5) + 10.0) * u
	var inner := Ring.new(_c, middle.rx - stagger * 1.2, middle.ry - stagger)
	# Each area's share of the outer ring: enough for its policies there and for its
	# indicators on the middle ring over the same angle (in one row or two), with a gap
	# between areas. A few passes settle it, since an angle covers less of the middle ring
	# at the top and bottom than at the sides.
	var area_gap := 22.0 * u
	var p_need := []
	var i_need := []
	for a in areas:
		var p := area_gap
		for key in a["policies"]:
			p += (2.0 * RADIUS[nodes[key]["tier"]] + 32.0) * u  # stage S13.5: room for labels on a fuller rim
			if nodes[key]["tier"] == 3:  # a label at rest wants room beside its node too
				p += 26.0 * u
		var m := area_gap
		for key in a["indicators"]:
			m += (2.0 * RADIUS[nodes[key]["tier"]] + 20.0) * u
		var name_font := Palette.display(600, 2)
		var name_w := name_font.get_string_size(str(a["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(14.0 * u))).x
		p_need.append(maxf(p, name_w * 1.15 + area_gap))
		i_need.append(m)
		a["rows"] = 1
	var start := outer.fraction(TAU - PI * 0.16) if areas.size() > 2 else 0.0
	var shares := []
	for i in areas.size():
		shares.append(maxf(p_need[i], i_need[i] * outer.length() / middle.length()))
	for attempt in 6:
		var total := 0.0
		for s in shares:
			total += s
		var f := start
		var short := false
		for i in areas.size():
			var share: float = shares[i] / total
			var span := _span(middle, outer.angle(f), outer.angle(f + share)) * middle.length()
			var rows := 1 if i_need[i] <= span else 2
			areas[i]["rows"] = rows
			var wanted: float = i_need[i] / rows
			if wanted > span * 1.001:
				shares[i] *= wanted / span
				short = true
			f += share
		if not short:
			break
	var total_share := 0.0
	for s in shares:
		total_share += s
	# Stage S13.6: a board with more nodes than its rings hold draws them smaller, never
	# overlapping (down to two thirds of their size).
	_node_scale = clampf(outer.length() / total_share, 0.66, 1.0)
	var rim := Ring.new(_c, outer.rx + RADIUS[3] * u + 16.0 * u, outer.ry + RADIUS[3] * u + 12.0 * u)
	_arcs.clear()
	_arc_ends.clear()
	_rim.clear()
	_spokes.clear()
	var f := start
	for i in areas.size():
		var a: Dictionary = areas[i]
		var share: float = shares[i] / total_share
		var pad := area_gap * 0.5 / outer.length()
		_place_row(a["policies"], outer, f + pad, f + share - pad)
		var from := outer.angle(f)
		var to := outer.angle(f + share)
		a["from"] = from
		a["to"] = to
		var m0 := middle.fraction(from)
		var m1 := m0 + _span(middle, from, to)
		var mpad := area_gap * 0.5 / middle.length()
		if a["rows"] == 2:
			var front := []
			var back := []
			for k in a["indicators"].size():
				(front if k % 2 == 0 else back).append(a["indicators"][k])
			_place_row(front, middle, m0 + mpad, m1 - mpad)
			var i0 := inner.fraction(from)
			var i1 := i0 + _span(inner, from, to)
			var ipad := area_gap * 0.5 / inner.length()
			# The back row sits between the front row's nodes.
			var step := (i1 - i0 - 2.0 * ipad) / maxf(front.size(), 1)
			_place_row(back, inner, i0 + ipad + step * 0.5, i1 - ipad + (step * 0.5 if back.size() < front.size() else 0.0))
		else:
			_place_row(a["indicators"], middle, m0 + mpad, m1 - mpad)
		var polar_share := fposmod(to - from, TAU)
		if areas.size() > 1:
			_spokes.append([rim.at(rim.fraction(from)), inner.at(inner.fraction(from)).lerp(_c, 0.0)])
		_rim_name(a, rim, from + polar_share * 0.5, polar_share)
		f += share
	# Interest groups on a ring round the centre; the centre itself. Stage S13.4: with groups
	# the medallion is smaller, so the groups have a band of their own.
	var group_keys := keys_of_unordered("group")  # the scenario's order (dictionaries keep it)
	var centre_r := clampf(minf(inner.ry, middle.ry) * 0.62, 70.0 * u, 128.0 * u)
	if not group_keys.is_empty():
		centre_r = clampf(middle.ry * 0.34, 60.0 * u, 96.0 * u)
	nodes["centre"]["pos"] = _c
	nodes["centre"]["r"] = centre_r
	_group_ring = null
	if not group_keys.is_empty():
		_place_groups(group_keys, centre_r, middle)
	_guides = [_outline(outer), _outline(middle)] + ([_outline(_group_ring)] if _group_ring != null else [])
	_order_nodes()
	set_flags(_flags, false)
	_place_labels()
	if _link_key != "":
		_tessellate()


## How far round a ring the polar angles from rom to 	o (clockwise) reach, as a fraction.
func _span(ring: Ring, from: float, to: float) -> float:
	var s := fposmod(ring.fraction(to) - ring.fraction(from), 1.0)
	return s if s > 1e-6 else 1.0  # the whole way round


func keys_of_unordered(kind: String) -> Array:
	return nodes.keys().filter(func(k): return nodes[k]["kind"] == kind)


func _place_row(keys: Array, ring: Ring, f0: float, f1: float) -> void:
	var n := keys.size()
	for k in n:
		var node: Dictionary = nodes[keys[k]]
		node["pos"] = ring.at(f0 + (f1 - f0) * (float(k) + 0.5) / float(n))
		node["r"] = RADIUS[node["tier"]] * _unit * _node_scale


## Stage S13.4: the groups on an ellipse round the centre, in their families with a gap
## between families, the first family centred at the top, each taking room for its size.
## Stage S13.6: more groups than the ring holds widen it towards the indicators (never onto
## one), and a ring that cannot clear them narrows; if the groups still do not fit (their
## padding may close to half first), they are drawn smaller.
func _place_groups(keys: Array, centre_r: float, middle: Ring) -> void:
	_group_scale = 1.0
	for attempt in 3:
		var room := []  # each group's [gap before it, room it takes]
		var total := 0.0
		var widest := 0.0
		var last := ""
		for key in keys:
			var n: Dictionary = nodes[key]
			n["r"] = group_radius(n)
			widest = maxf(widest, n["r"])
			var gap := FAMILY_GAP * _unit if last != "" and n["family"] != last else 0.0
			last = n["family"]
			room.append([gap, 2.0 * n["r"] + 30.0 * _unit])
			total += gap + 2.0 * n["r"] + 30.0 * _unit
		total += FAMILY_GAP * _unit  # between the last family and the first
		var tight := total - 15.0 * _unit * keys.size()
		var span := maxf(middle.ry - centre_r, 1.0)
		var lowest := (widest + 8.0 * _unit) / span
		var k := GROUP_RING.y
		_spread_groups(keys, room, total, _group_ring_at(k, centre_r, middle))
		while _groups_collide(keys) and k - 0.02 >= lowest:
			k -= 0.02
			_spread_groups(keys, room, total, _group_ring_at(k, centre_r, middle))
		while _group_ring.length() < tight and k + 0.02 <= 0.9:
			_spread_groups(keys, room, total, _group_ring_at(k + 0.02, centre_r, middle))
			if _groups_collide(keys):
				_spread_groups(keys, room, total, _group_ring_at(k, centre_r, middle))
				break
			k += 0.02
		if _group_ring.length() >= tight or attempt == 2:
			return
		_group_scale *= maxf(_group_ring.length() / tight, 0.8)


func _group_ring_at(k: float, centre_r: float, middle: Ring) -> Ring:
	return Ring.new(_c, centre_r + (middle.rx - centre_r) * k * GROUP_RING.x / GROUP_RING.y, centre_r + (middle.ry - centre_r) * k)


## True when a group touches an indicator.
func _groups_collide(keys: Array) -> bool:
	for g in keys:
		for i in keys_of_unordered("indicator"):
			if (nodes[g]["pos"] as Vector2).distance_to(nodes[i]["pos"]) < nodes[g]["r"] + nodes[i]["r"] + 6.0 * _unit:
				return true
	return false


func _spread_groups(keys: Array, room: Array, total: float, ring: Ring) -> void:
	_group_ring = ring
	var f := 0.0
	for i in range(1, keys.size()):
		if nodes[keys[i]]["family"] != nodes[keys[0]]["family"]:
			break
		f -= (room[i - 1][1] + room[i][1]) / 4.0
	for i in keys.size():
		if i > 0:
			f += (room[i][0] + (room[i - 1][1] + room[i][1]) / 2.0)
		nodes[keys[i]]["pos"] = ring.at(f / total)


## A group's radius: its area follows its share of the electorate (stage S13.5: eight in ten,
## the motorists, gives a node of radius GROUP_MAX), never smaller than 14 pixels at a unit
## scale of 1. Quantised, so a month's small change in a share leaves the board as it was.
func group_radius(n: Dictionary) -> float:
	var share: float = n.get("share_value", -1.0)
	if share < 0.0:
		share = 0.12
	return snappedf(14.0 + (GROUP_MAX - 14.0) * sqrt(clampf(share / 0.8, 0.0, 1.0)), 1.0) * _unit * _group_scale


func _outline(ring: Ring) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 181:
		points.append(ring.at(float(i) / 180.0))
	return points


## Sets an area's name along the rim, centred on its sector, upright everywhere: letters
## run clockwise over the top half and anticlockwise along the bottom.
func _rim_name(a: Dictionary, ring: Ring, middle: float, share: float) -> void:
	var font := Palette.display(600, 2)
	var size_px := int(roundf(14.0 * _unit))
	var text := str(a["name"]).to_upper()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var f_mid := ring.fraction(middle)
	var per := 1.0 / ring.length()
	var top := cos(middle) > -0.05  # angle from the top: the upper half reads clockwise
	var room := _span(ring, middle - share * 0.5, middle + share * 0.5) * 0.92
	if width * per > room:
		text = ""  # an area too narrow for its name keeps only its arc
		width = 0.0
	var x := -width / 2.0
	var fa := ring.fraction(middle - share * 0.44)
	var fb := ring.fraction(middle + share * 0.44)
	if fb < fa:
		fb += 1.0
	# Stage S13.4: the arc breaks behind the name, so no letter is struck through.
	var fm := f_mid if f_mid >= fa else f_mid + 1.0
	var half := (width / 2.0 + 10.0 * _unit) * per if text != "" else 0.0
	for piece in [[fa, fm - half, 0], [fm + half, fb, 1]]:
		if piece[1] - piece[0] <= per:
			continue
		var arc := PackedVector2Array()
		for i in 31:
			arc.append(ring.at(lerpf(piece[0], piece[1], i / 30.0)))
		_arcs.append(arc)
		_arc_ends.append(piece[2])  # which end of the area's arc gets a tick: 0 its start, 1 its end
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var along := (x + w / 2.0) * per
		var f := f_mid + along if top else f_mid - along
		var p := ring.at(f)
		var q := ring.at(f + per * (1.0 if top else -1.0))
		var rot := (q - p).angle()
		_rim.append([ch, p, rot, w, size_px])
		x += w


func _order_nodes() -> void:
	order = PackedStringArray()
	for kind in ["centre", "group", "indicator", "policy", "introduce", "flag"]:
		for key in nodes:
			if nodes[key]["kind"] == kind:
				order.append(key)


## Stage S13.4: a label for every node that has room for one at rest, the largest nodes
## first. Policies label towards the centre (outward is the rim); indicators and groups
## outward from the centre, then below; each tries a wide label, then one on two lines,
## then the other places round the node, and takes the first that clears every node, flag,
## the rim and the labels already placed. A node with no room shows its label on hover and
## when zoomed in. A group's label carries its approval on a line of its own.
func _place_labels() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	var placed: Array = []
	var font := Palette.display(500)
	var keys: Array = Array(order).filter(func(k): return not nodes[k]["kind"] in ["centre", "flag"])
	keys.sort_custom(func(a, b): return _label_rank(a) > _label_rank(b))
	for key in nodes:
		nodes[key]["label_rect"] = Rect2()
		nodes[key]["rest"] = false
	for key in keys:
		var node: Dictionary = nodes[key]
		var size_px := node_label_size(node)
		var best := Rect2()
		var first := Rect2()
		var extra := (size_px + 2.0) if node["kind"] == "group" else 0.0  # the approval line
		# Stage S13.6: a second pass tries every way round the node, and a narrower label.
		var widths := [130.0, 84.0] if node["tier"] == 3 else [112.0, 76.0]
		var passes := [[widths, false], [widths + [widths[1] * 0.72], true]]
		for attempt in passes:
			if best.size != Vector2.ZERO:
				break
			var found := _find_label(node, key, placed, attempt[0], attempt[1], font, size_px, extra)
			best = found[0]
			if first.size == Vector2.ZERO:
				first = found[1]
		node["rest"] = best.size != Vector2.ZERO
		if best.size == Vector2.ZERO:
			best = first
		node["label_rect"] = best
		if node["rest"]:
			placed.append(best)


## Stage S13.6: the first clear place for a node's label at these widths: [rect, the
## first place tried]; `round_about` adds every way round the node, nearest the preferred
## way first. Sets the node's "lines" to those of the place found (or first tried).
func _find_label(node: Dictionary, key: String, placed: Array, widths: Array, round_about: bool, font: Font, size_px: int,
		extra: float) -> Array:
	var first := Rect2()
	for width in widths:
		var lines := wrap_label(str(node["label"]), font, size_px, width * _unit)
		var w := 0.0
		for line in lines:
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
		if extra > 0.0:
			w = maxf(w, Palette.text(600).get_string_size("100%", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
		var h := lines.size() * (size_px + 2.0) + extra
		var p: Vector2 = node["pos"]
		var r: float = node["r"] + {"policy": 9.0, "group": 6.0}.get(node["kind"], 4.0) * _unit
		var out := p - _c
		out = Vector2(out.x / maxf(size.x, 1.0), out.y / maxf(size.y, 1.0)).normalized()
		var below := Vector2(0, r + h / 2.0)
		var above := Vector2(0, -r - h / 2.0)
		var side := Vector2((r + w / 2.0 + 2.0) * (signf(out.x) if out.x != 0.0 else 1.0), 0)
		var lean := Vector2(w / 2.0 * signf(out.x), 0)
		var outward: Vector2 = side if absf(out.x) > 0.8 else (below if out.y > 0.0 else above)
		var candidates := [outward, below, above, side, -side, below + lean, above + lean, below - lean, above - lean]
		if node["kind"] in ["policy", "introduce"]:
			candidates = [-outward, below, above, -side, side, below - lean, above - lean]
		if round_about:
			# Every way round the node, a label touching it, nearest the preferred way first.
			var prefer := (-out if node["kind"] in ["policy", "introduce"] else out).angle()
			var turns := []
			for k in 16:
				turns.append(k * TAU / 16.0)
			turns.sort_custom(func(x, y): return absf(angle_difference(x, prefer)) < absf(angle_difference(y, prefer)))
			candidates = turns.map(func(t): return Vector2.from_angle(t) * (r + 2.0) + Vector2(cos(t) * w, sin(t) * h) / 2.0)
			# and, failing those, a little further off.
			for far in [10.0, 18.0]:
				candidates += turns.map(func(t): return Vector2.from_angle(t) * (r + far * _unit) + Vector2(cos(t) * w, sin(t) * h) / 2.0)
		for offset in candidates:
			var rect := Rect2(p + offset - Vector2(w, h) / 2.0, Vector2(w, h))
			if first.size == Vector2.ZERO:
				first = rect
				node["lines"] = lines
			if _clear(rect, key, placed):
				node["lines"] = lines
				return [rect, first]
	return [Rect2(), first]


## Which labels claim their room first: the largest nodes, groups before indicators before
## policies of the same size.
func _label_rank(key: String) -> float:
	var n: Dictionary = nodes[key]
	return float(n["tier"]) * 10.0 + {"group": 2.0, "indicator": 1.0}.get(n["kind"], 0.0) + float(n["r"]) / 1000.0


func _clear(rect: Rect2, own: String, placed: Array) -> bool:
	if not Rect2(Vector2.ZERO, size).grow(-4.0).encloses(rect):
		return false
	for key in nodes:
		if key == own:
			continue
		var n: Dictionary = nodes[key]
		if n["kind"] == "flag":
			if (n["hit"] as Rect2).grow(4.0).intersects(rect):
				return false
			continue
		if _rect_circle(rect, n["pos"], n["r"] + 3.0 * _unit):
			return false
	for r in placed:
		if (r as Rect2).grow(3.0).intersects(rect):
			return false
	for g in _rim:
		var gp: Vector2 = g[1]
		if rect.grow(6.0).has_point(gp):
			return false
	for arc in _arcs:
		for p in arc:
			if rect.grow(3.0).has_point(p):
				return false
	return true


static func _rect_circle(rect: Rect2, c: Vector2, r: float) -> bool:
	var q := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return q.distance_to(c) < r


func label_size() -> int:
	return int(roundf(clampf(14.0 * _unit, 13.0, 22.0)))


## Stage S13.4: two sizes of label, the larger for the largest nodes.
func node_label_size(n: Dictionary) -> int:
	# Stage S13.6: a crowded rim's smaller nodes take smaller labels too (never under 11 pixels).
	var crowd := _node_scale if n["kind"] in ["policy", "indicator", "introduce"] else _group_scale
	var full := label_size() if n["tier"] == 3 else maxi(12, int(roundf(label_size() * 0.86)))
	return maxi(11, int(roundf(full * lerpf(1.0, crowd, 0.6))))


## Splits a label into at most two lines of at most `width` pixels, never cutting a word.
static func wrap_label(text: String, font: Font, size_px: int, width: float) -> PackedStringArray:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= width:
		return PackedStringArray([text])
	var words := text.split(" ")
	var best := PackedStringArray([text])
	var best_w := INF
	for cut in range(1, words.size()):
		var a := " ".join(words.slice(0, cut))
		var b := " ".join(words.slice(cut))
		var w := maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
		if w < best_w:
			best_w = w
			best = PackedStringArray([a, b])
	return best


## For the board check: pairs of nodes (or labels shown at rest) that overlap, as text.
func overlaps() -> PackedStringArray:
	var out := PackedStringArray()
	var keys := order
	for i in keys.size():
		var a: Dictionary = nodes[keys[i]]
		for j in range(i + 1, keys.size()):
			var b: Dictionary = nodes[keys[j]]
			if (a["pos"] as Vector2).distance_to(b["pos"]) < a["r"] + b["r"] + 2.0:
				out.append("%s and %s" % [keys[i], keys[j]])
		if a.get("rest", false):
			if not Rect2(Vector2.ZERO, size).encloses(a["label_rect"]):
				out.append("label of %s off the board" % keys[i])
			for j in keys.size():
				if j == i:
					continue
				var b: Dictionary = nodes[keys[j]]
				if b["kind"] == "flag":
					if (b["hit"] as Rect2).intersects(a["label_rect"]):
						out.append("label of %s and %s" % [keys[i], keys[j]])
				elif _rect_circle(a["label_rect"], b["pos"], b["r"]):
					out.append("label of %s and %s" % [keys[i], keys[j]])
				if b.get("rest", false) and j > i and (a["label_rect"] as Rect2).intersects(b["label_rect"]):
					out.append("labels of %s and %s" % [keys[i], keys[j]])
		if a["kind"] == "flag":
			for j in keys.size():
				var b: Dictionary = nodes[keys[j]]
				if b["kind"] != "flag" and _rect_circle(a["hit"], b["pos"], b["r"]):
					out.append("flag %s and %s" % [keys[i], keys[j]])
				elif b["kind"] == "flag" and j > i and (a["hit"] as Rect2).intersects(b["hit"]):
					out.append("flags %s and %s" % [keys[i], keys[j]])
			continue
		var r: float = a["r"]
		if not Rect2(Vector2.ZERO, size).grow(-2.0).encloses(Rect2(a["pos"] - Vector2(r, r), Vector2(r, r) * 2.0)):
			out.append("%s off the board" % keys[i])
	return out


# ---------------------------------------------------------------------------- view

func to_screen(p: Vector2) -> Vector2:
	return _c + (p - _c) * zoom + pan


func to_layout(s: Vector2) -> Vector2:
	return _c + (s - pan - _c) / zoom


## Back to the whole board.
func fit() -> void:
	var from_zoom := zoom
	var from_pan := pan
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(k: float) -> void:
		zoom = lerpf(from_zoom, 1.0, k)
		pan = from_pan.lerp(Vector2.ZERO, k)
		queue_layers(), 0.0, 1.0, 0.22)


func zoom_at(screen: Vector2, factor: float) -> void:
	var before := to_layout(screen)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	pan += screen - to_screen(before)
	_clamp_pan()
	queue_layers()


func _clamp_pan() -> void:
	var limit := size * 0.5 * maxf(zoom, 1.0)
	pan = pan.clamp(-limit, limit)


func queue_layers() -> void:
	for layer in [_base, _link_layer, _node_layer, _fx_layer]:
		if layer != null:
			layer.queue_redraw()


func node_at(screen: Vector2) -> String:
	var best := ""
	var best_d := INF
	for key in order:
		var n: Dictionary = nodes[key]
		var d := to_screen(n["pos"]).distance_to(screen)
		# Stage S13.6: one hit shape, unchanged by the hover lift, a little wider for the
		# node pointed at now, so its edge never flickers in and out.
		var r: float = n["r"] * zoom + (10.0 if key == hover else 4.0)
		if n["kind"] == "flag":
			if (n["hit"] as Rect2).has_point(to_layout(screen)):
				return key
			continue
		if d <= r and d < best_d:
			best = key
			best_d = d
	return best


func _gui_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		if _pressing and (event.position - _press).length() > 5.0:
			_dragging = true
		if _dragging:
			pan += event.relative
			_clamp_pan()
			queue_layers()
		else:
			_point(node_at(event.position))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_at(event.position, 1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = event.position
				_pressing = true
				_dragging = false
				grab_focus()
			else:
				var was_drag := _dragging
				_pressing = false
				_dragging = false
				if not was_drag:
					var key := node_at(event.position)
					if key != "":
						node_pressed.emit(key)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled or not is_visible_in_tree() or not event.pressed:
		return
	var step := 60.0
	var moves := {KEY_LEFT: Vector2(step, 0), KEY_RIGHT: Vector2(-step, 0), KEY_UP: Vector2(0, step), KEY_DOWN: Vector2(0, -step)}
	if moves.has(event.keycode):
		pan += moves[event.keycode]
		_clamp_pan()
		queue_layers()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		zoom_at(size / 2.0, 1.15)
	elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		zoom_at(size / 2.0, 1.0 / 1.15)
	elif event.keycode == KEY_HOME:
		fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _dragging:
		set_hover("")


## Stage S13.6: the pointer over `key` ("" over nothing): a new node is taken at once, but
## leaving one waits a moment, so crossing a gap or an edge does not blink the links.
func _point(key: String) -> void:
	if key == "" and hover != "":
		if _leave.is_stopped():
			_leave.start(LEAVE_GRACE)
		return
	set_hover(key)


## Points at a node (the pointer's, or a script's): lifts it and shows its links.
func set_hover(key: String) -> void:
	if _leave != null:
		_leave.stop()
	if key == hover:
		return
	if hover != "":
		_animate_lift(hover, 0.0)
	hover = key
	if key != "":
		_animate_lift(key, 1.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if key != "" else Control.CURSOR_ARROW
	_focus_changed()
	hover_changed.emit(key)


## Keeps a node's links shown while its popup is open ("" to let go).
func select(key: String) -> void:
	selected = key
	_focus_changed()


## New measured effects arrived. Stage S13.6: the links on screen stay steady. The same
## links are updated in place; links read from the formulas give way once, fading, to
## measured ones; measured links already shown are kept until the pointer moves on (the
## table's other levers shift each row's scale, which would reshuffle them while looked at).
func effects_changed() -> void:
	_reach.clear()
	_scales.clear()
	var key := focus_key()
	if key == "" or key != _link_key or not nodes.has(key):
		return
	var fresh := links_for(key)
	if _same_links(fresh, _links):
		for i in fresh.size():
			_links[i]["strength"] = fresh[i]["strength"]
		_link_layer.queue_redraw()
		return
	if _links.any(func(l): return l["measured"]):
		return
	_links = fresh
	_tessellate()
	link_sets += 1
	_link_fade = 0.0
	var tween := create_tween()
	tween.tween_property(self, "_link_fade", 1.0, 0.25)
	set_process(true)
	queue_layers()


static func _same_links(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["from"] != b[i]["from"] or a[i]["to"] != b[i]["to"] or a[i]["sign"] != b[i]["sign"] or a[i]["measured"] != b[i]["measured"]:
			return false
	return true


func focus_key() -> String:
	return hover if hover != "" else selected


func _animate_lift(key: String, to: float) -> void:
	if _lift_tweens.has(key) and (_lift_tweens[key] as Tween).is_valid():
		(_lift_tweens[key] as Tween).kill()
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_lift[key] = v
		_node_layer.queue_redraw(), _lift.get(key, 0.0), to, 0.09)
	_lift_tweens[key] = tween


func _focus_changed() -> void:
	var key := focus_key()
	if key == _link_key:
		return
	_link_key = key
	_links = links_for(key)
	link_sets += 1
	_link_fade = 1.0
	_tessellate()
	if _tween_links != null and _tween_links.is_valid():
		_tween_links.kill()
	_draw_in = 0.0
	_tween_links = create_tween()
	_tween_links.tween_property(self, "_draw_in", 1.0, 0.15)
	if _tween_dim != null and _tween_dim.is_valid():
		_tween_dim.kill()
	_tween_dim = create_tween()
	var dims: bool = key != "" and str(nodes.get(key, {}).get("kind", "")) in ["policy", "indicator", "group"]
	_tween_dim.tween_property(self, "_dim", 1.0 if dims else 0.0, 0.12)
	set_process(true)
	queue_layers()


func _process(delta: float) -> void:
	_flow += delta
	var busy := not _links.is_empty() or _dim > 0.0
	if not _pulses.is_empty():
		for key in _pulses.keys():
			_pulses[key] += delta
			if _pulses[key] > 1.6:
				_pulses.erase(key)
		_fx_layer.queue_redraw()
		busy = true
	if not _links.is_empty():
		_link_layer.queue_redraw()
	if _draw_in < 1.0 or (_dim > 0.0 and _dim < 1.0):
		_node_layer.queue_redraw()
	if not busy:
		set_process(false)


# ---------------------------------------------------------------------------- links

## The links of a node: a policy's measured effects a year on (or, until they exist, the
## nodes its levers reach through the model's formulas, drawn neutral); an indicator's or a
## group's strongest causes among the policies, the same table read the other way.
func links_for(key: String) -> Array:
	if key == "" or not nodes.has(key):
		return []
	var node: Dictionary = nodes[key]
	var out: Array = []
	var targets := _targets()
	if node.get("ghost", false):
		return out  # stage S13.5: not in force yet; its popup's "In a year" says what it would do
	if node["kind"] == "policy":
		var best := {}  # target key -> [signed strength, measured]
		# A policy of several levers is measured by its first, the one its gauge shows (the
		# basic rate for Income tax), so a link's direction always means "raising this".
		# Stage S13.4: each effect is weighed against the target's own scale, what a typical
		# policy does to it, so a rate and an amount of money compare fairly.
		for lever in (node["levers"] as PackedStringArray).slice(0, 1):
			if effects.has(lever):
				for row in effects[lever]:
					var target := _target_of_row(row, targets)
					if target == "":
						continue
					var raw := float(effects[lever][row])
					var s := raw / maxf(_row_scale(row), 1e-12)
					if absf(raw) >= LINK_FLOOR and (not best.has(target) or absf(s) > absf(best[target][0])):
						best[target] = [s, true]
		if best.is_empty():
			var shown := {}
			for t in targets:
				shown[nodes[t]["name"]] = t
			for lever in node["levers"]:
				for name in _cached_reach(lever, shown):
					best[shown[name]] = [0.0, false]
		# Ranked by that weight, capped at ten times the typical (a row few policies touch can
		# swing wildly), times the importance of the node (its size, squared).
		var score := func(k: String) -> float: return minf(absf(best[k][0]), 10.0) * pow(float(nodes[k]["tier"]), 2.0)
		var ranked := best.keys()
		ranked.sort_custom(func(a, b): return score.call(a) > score.call(b))
		var chosen: Array = ranked.filter(func(t): return nodes[t]["kind"] == "indicator").slice(0, MAX_LINKS)
		chosen.append_array(ranked.filter(func(t): return nodes[t]["kind"] == "group").slice(0, MAX_GROUP_LINKS))
		# The budget balance is always shown for a policy that moves it.
		var balance := _target_of_row(str(budget_row), targets)
		if balance != "" and best.has(balance) and not chosen.has(balance):
			chosen.append(balance)
		for t in chosen:
			out.append({"from": key, "to": t, "sign": signf(best[t][0]), "strength": clampf(score.call(t) / maxf(score.call(ranked[0]), 1e-12), 0.15, 1.0) if best[t][1] else 0.35,
				"measured": best[t][1]})
	elif node["kind"] in ["indicator", "group"]:
		var causes := movers(key)
		var top := 1e-12
		for c in causes:
			top = maxf(top, absf(c[1]))
		for c in causes.slice(0, MAX_LINKS):
			out.append({"from": c[0], "to": key, "sign": signf(c[1]), "strength": absf(c[1]) / top if c[2] else 0.35, "measured": c[2]})
	return out


## The policies that move an indicator or group most: [policy key, signed strength,
## measured], strongest first; from the structure when nothing is measured yet.
func movers(key: String) -> Array:
	var node: Dictionary = nodes.get(key, {})
	return movers_for(str(node.get("row", "")), str(node.get("name", "")))


## The same for any result row (a "-" in front negates) and its catalogue entry, on the
## board or not (a budget line).
func movers_for(row_key: String, name: String) -> Array:
	var row := row_key.trim_prefix("-")
	var flip := -1.0 if row_key.begins_with("-") else 1.0
	var out: Array = []
	for p in keys_of("policy"):
		var best := 0.0
		var found := false
		for lever in (nodes[p]["levers"] as PackedStringArray).slice(0, 1):
			if effects.has(lever) and effects[lever].has(row):
				var s := float(effects[lever][row]) * flip
				if absf(s) >= LINK_FLOOR and absf(s) > absf(best):
					best = s
					found = true
		if found:
			out.append([p, best, true])
	if out.is_empty() and name != "":
		var shown := {}
		for t in _targets():
			shown[nodes[t]["name"]] = t
		var on_board := shown.has(name)
		if not on_board:
			shown = {name: true}
		for p in keys_of("policy"):
			for lever in nodes[p]["levers"]:
				var hit: bool = (_cached_reach(lever, shown) if on_board else reaches(lever, shown)).has(name)
				if hit:
					out.append([p, 0.0, false])
					break
	out.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	return out


## A row's own scale: how much a typical lever moves it in the effects table (the median
## of the moves above the floor), so a policy's effect counts by how unusual it is.
func _row_scale(row: String) -> float:
	if not _scales.has(row):
		var moves: Array = []
		for lever in effects:
			var m := absf(float(effects[lever].get(row, 0.0)))
			if m >= LINK_FLOOR:
				moves.append(m)
		moves.sort()
		_scales[row] = moves[moves.size() / 2] if not moves.is_empty() else 1.0
	return _scales[row]


func _targets() -> Array:
	return Array(order).filter(func(k): return nodes[k]["kind"] in ["indicator", "group"])


func _target_of_row(row: String, targets: Array) -> String:
	for t in targets:
		if str(nodes[t]["row"]).trim_prefix("-") == row:
			return t
	return ""


func _cached_reach(lever: String, shown: Dictionary) -> PackedStringArray:
	if not _reach.has(lever):
		_reach[lever] = reaches(lever, shown)
	return _reach[lever]


## For tests and the popups: the keys a node links to (or from) now.
func linked(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for link in links_for(key):
		out.append(link["to"] if link["from"] == key else link["from"])
	return out


## The links' curves, worked out once per change of focus, in layout coordinates.
func _tessellate() -> void:
	for link in _links:
		var a: Dictionary = nodes[link["from"]]
		var b: Dictionary = nodes[link["to"]]
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		var mid := (pa + pb) / 2.0
		var normal := (pb - pa).orthogonal().normalized()
		# Bend towards the centre, so links sweep round the inside of the board.
		if normal.dot(_c - mid) < 0.0:
			normal = -normal
		# Stage S13.6: never under the centre medallion: the gentlest bend, either way, whose
		# curve clears it; failing that, the widest tried.
		var keep_out: float = nodes["centre"]["r"] + 10.0 * _unit if nodes.has("centre") else 0.0
		var points := PackedVector2Array()
		for bend in [0.22, -0.22, 0.4, -0.4, 0.6, -0.6, 0.85, -0.85]:
			points = _curve(a, b, mid + normal * pa.distance_to(pb) * bend)
			var clear := true
			for p in points:
				if p.distance_to(_c) < keep_out:
					clear = false
					break
			if clear:
				break
		link["points"] = points


func _curve(a: Dictionary, b: Dictionary, control: Vector2) -> PackedVector2Array:
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	var start: Vector2 = pa + (control - pa).normalized() * (a["r"] + 3.0 * _unit)
	var end: Vector2 = pb + (control - pb).normalized() * (b["r"] + 7.0 * _unit)
	var points := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		points.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
	return points


# ---------------------------------------------------------------------------- refresh

## Each node's state from the game: `value_of(row)` and `before_of(row)` read result rows
## (a "-" in front negates), `lever_of(name)` a lever's setting and `start_of(name)` where it
## began, `pending` the changes waiting. Nodes that moved notably pulse.
func refresh(value_of: Callable, before_of: Callable, lever_of: Callable, start_of: Callable, pending: Dictionary, pulse := false) -> void:
	# Stage S13.5: policies come onto the board and leave it as bills pass.
	var relayout := _sync(lever_of, pending)
	for key in nodes:
		var n: Dictionary = nodes[key]
		if n["kind"] == "introduce":
			n["value"] = "%d to choose from" % int(n.get("count", 0))
		if n["kind"] == "policy":
			var lever: String = n["levers"][0]
			var entry: Dictionary = _entries.get(lever, {})
			var now: Variant = lever_of.call(lever)
			var start: Variant = start_of.call(lever)
			n["fraction"] = _gauge(entry, now, start)
			n["pending"] = -1.0
			n["waiting"] = 0
			for l in n["levers"]:
				if pending.has(l):
					n["waiting"] += 1
			if pending.has(lever):
				n["pending"] = _gauge(entry, pending[lever], start)
			n["value"] = fmt.value(entry, now, false, false) if fmt != null and now != null else ""
			if n.get("ghost", false):
				n["fraction"] = -1.0
				n["value"] = "to be introduced: %s" % fmt.value(entry, pending[lever], false, false) if fmt != null else ""
			elif pending.has(lever) and is_off(n, pending[lever]):
				n["value"] += " · to be repealed"
		elif n["kind"] in ["indicator", "group"]:
			var entry: Dictionary = _entries.get(n["name"], {})
			var now: Variant = value_of.call(n["row"])
			var was: Variant = before_of.call(n["row"])
			n["value"] = fmt.value(entry, now, true, false) if fmt != null else ""
			n["trend"] = 0
			# Stage S13.6: before the first month there is nothing to show yet, and it says so.
			n["change"] = "awaiting the first month's figures" if now == null else ""
			if now != null and was != null and typeof(now) != TYPE_BOOL:
				var d := float(now) - float(was)
				var scale := maxf(absf(float(was)), 1e-9)
				var notable := absf(d) * 100.0 >= 0.1 if fmt != null and fmt.is_rate(entry) else absf(d) / scale >= 0.005
				n["trend"] = 0 if d == 0.0 else (1 if d > 0.0 else -1)
				n["change"] = fmt.change(entry, d) if fmt != null else ""
				if pulse and notable:
					_pulses[key] = 0.0
			if n["kind"] == "group":
				# Stage S13.4: the gauge shows approval; a group whose approval is nought for a
				# reason the scenario gives (no governing candidate stands) shows a dash.
				n["fraction"] = clampf(float(now), 0.0, 1.0) if now != null else -1.0
				if now != null and absf(float(now)) < 0.0005 and str(n.get("note", "")) != "":
					n["value"] = "–"
					n["change"] = ""
					n["trend"] = 0
				var share: Variant = value_of.call(str(n.get("share", ""))) if str(n.get("share", "")) != "" else null
				if share != null:
					var old_r := group_radius(n)
					n["share_value"] = float(share)
					relayout = relayout or group_radius(n) != old_r
	if not _pulses.is_empty():
		set_process(true)
	if relayout:
		_relayout_smoothly()  # a group grew or shrank a size
	queue_layers()


## Stage S13.6: lays the board out again with the nodes gliding to their new places (the
## groups take their sizes once their shares are first known), so nothing jumps.
func _relayout_smoothly() -> void:
	var before := {}
	for key in nodes:
		before[key] = [nodes[key]["pos"], nodes[key]["r"]]
	layout()
	var after := {}
	for key in nodes:
		if before.has(key) and before[key][0] != Vector2.ZERO:
			after[key] = [nodes[key]["pos"], nodes[key]["r"]]
	if after.is_empty() or DisplayServer.get_name() == "headless":
		return
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(k: float) -> void:
		for key in after:
			if nodes.has(key):
				nodes[key]["pos"] = (before[key][0] as Vector2).lerp(after[key][0], k)
				nodes[key]["r"] = lerpf(before[key][1], after[key][1], k)
		if _link_key != "":
			_tessellate()
		queue_layers(), 0.0, 1.0, 0.45)


## Where a setting sits in its range, 0 to 1, for the gauge. Spending lines have ranges far
## wider than play (up to ten times the start); a gauge over those would never move, so for
## a range more than four times the start the gauge reads 0 to twice the start.
func _gauge(entry: Dictionary, v: Variant, start_value: Variant) -> float:
	if v == null or not entry.get("has_range", false):
		return -1.0
	var lo := float(entry["min"])
	var hi := float(entry["max"])
	var start := float(start_value) if start_value != null else 0.0
	if start > 0.0 and lo == 0.0 and hi > 4.0 * start:
		hi = 2.0 * start
	if hi <= lo:
		return -1.0
	return clampf((float(v) - lo) / (hi - lo), 0.0, 1.0)


## The situations in force and the decisions taken, as flags beside the centre: each
## {key, text, tone ("good", "bad", "plain", "ask"), doc}.
func set_flags(flags: Array, relabel := true) -> void:
	var same := flags == _flags
	_flags = flags
	for key in nodes.keys():
		if nodes[key]["kind"] == "flag":
			nodes.erase(key)
	var font := Palette.text(500)
	var size_px := int(roundf(clampf(14.0 * _unit, 14.0, 20.0)))
	var centre_node: Dictionary = nodes.get("centre", {})
	if centre_node.is_empty():
		return
	# Stacked beside the centre, in the open paper inside the indicator ring: the first
	# column to its left (right-aligned to it), a second to its right. Stage S13.4: with
	# groups round the centre, in the window's corners instead, outside the rim, the first in
	# the top left, then top right, bottom left, bottom right.
	var cornered := not keys_of_unordered("group").is_empty()
	var h := size_px + 12.0 * _unit
	var step := h + 8.0 * _unit
	var per_column := 5
	for i in flags.size():
		var f: Dictionary = flags[i]
		var w := font.get_string_size(str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + 34.0 * _unit
		var column := i / per_column
		var count := mini(per_column, flags.size() - column * per_column)
		var y: float = _c.y - (count * step - 8.0 * _unit) / 2.0 + (i % per_column) * step
		var gap: float = centre_node["r"] + 26.0 * _unit
		var x: float = _c.x - gap - w if column % 2 == 0 else _c.x + gap
		if cornered:
			var corner := i % 4
			var slot := i / 4
			var margin := 10.0 * _unit
			x = margin if corner % 2 == 0 else size.x - margin - w
			y = margin + slot * step if corner < 2 else size.y - margin - h - slot * step
		var key := "flag:" + str(f["key"])
		_add(key, "flag", str(f["text"]), "", 1, "", PackedStringArray(), str(f.get("row", "")), str(f.get("name", "")))
		nodes[key]["tone"] = str(f.get("tone", "plain"))
		nodes[key]["value"] = str(f["text"]) + str(f.get("since", ""))
		nodes[key]["doc"] = str(f.get("doc", ""))
		nodes[key]["hit"] = Rect2(x, y, w, h)
		nodes[key]["pos"] = (nodes[key]["hit"] as Rect2).get_center()
		nodes[key]["r"] = 0.0
	_order_nodes()
	# Labels make room for flags in the corners, so new flags place them again.
	if cornered and relabel and not same:
		_place_labels()
	queue_layers()


func flag_text(key: String) -> String:
	return str(nodes.get("flag:" + key, {}).get("value", ""))


# ---------------------------------------------------------------------------- drawing

func _alpha(key: String) -> float:
	var focus := focus_key()
	if focus == "" or focus == "centre" or _dim <= 0.0:
		return 1.0
	if key == focus:
		return 1.0
	for link in _links:
		if link["from"] == key or link["to"] == key:
			return 1.0
	return lerpf(1.0, 0.26, _dim)


func _draw_base() -> void:
	# Faint dotted guides for the two rings, as on a printed chart.
	for points in _guides:
		var pts := PackedVector2Array()
		for p in points:
			pts.append(to_screen(p))
		for i in range(0, pts.size() - 1, 2):
			_base.draw_line(pts[i], pts[i + 1], Color(Palette.INK, 0.13), 1.0)
	# Dotted spokes between the areas, from the rim to the middle ring.
	for spoke in _spokes:
		var a := to_screen(spoke[0])
		var b := to_screen(spoke[1])
		var n := int(a.distance_to(b) / 9.0)
		for k in n:
			if k % 2 == 0:
				_base.draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(Palette.INK, 0.16), 1.0)
	# Each area's arc along the rim, with ticks at its ends; its name set along it.
	for k in _arcs.size():
		var pts := PackedVector2Array()
		for p in _arcs[k]:
			pts.append(to_screen(p))
		if pts.size() > 1:
			_base.draw_polyline(pts, Color(Palette.INK, 0.55), 1.5, true)
			for end in [0 if _arc_ends[k] == 0 else pts.size() - 1]:
				var n := (pts[end] - to_screen(_c)).normalized()
				_base.draw_line(pts[end] - n * 4.0, pts[end] + n * 4.0, Color(Palette.INK, 0.55), 1.5)
	var font := Palette.display(600, 2)
	for g in _rim:
		var p := to_screen(g[1])
		_base.draw_set_transform(p, g[2], Vector2.ONE * sqrt(zoom))
		_base.draw_string(font, Vector2(-g[3] / 2.0, g[4] * 0.36), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, g[4], Palette.INK)
	_base.draw_set_transform(Vector2.ZERO)


func _draw_links() -> void:
	for link in _links:
		var points: PackedVector2Array = link["points"]
		var pts := PackedVector2Array()
		var count := maxi(2, int(ceil(points.size() * _draw_in)))
		for i in count:
			pts.append(to_screen(points[mini(i, points.size() - 1)]))
		var colour := Color(Palette.INK, 0.55)
		if link["measured"]:
			colour = Palette.BLUE if link["sign"] >= 0.0 else Palette.BRICK
		colour.a *= _link_fade
		var width := (1.5 + 4.0 * float(link["strength"])) * sqrt(zoom) * _unit
		# A faint full line under flowing dashes; the dashes run faster for a stronger link.
		_link_layer.draw_polyline(pts, Color(colour, 0.28 * _link_fade), width, true)
		_dashes(pts, colour, width, 14.0 * _unit, 9.0 * _unit, _flow * (30.0 + 50.0 * float(link["strength"])) * _unit)
		if _draw_in >= 1.0:
			var tip := pts[pts.size() - 1]
			var dir := (tip - pts[pts.size() - 3]).normalized()
			var side := dir.orthogonal()
			var head := (8.0 + width * 1.4)
			_link_layer.draw_colored_polygon(PackedVector2Array([tip, tip - dir * head + side * head * 0.55, tip - dir * head - side * head * 0.55]), colour)
			if link["measured"]:
				# The direction as a glyph as well as a colour, on the link mid-way: a square tag
				# with a plus or a minus, unlike the round rise and fall badges on the nodes.
				var mid := pts[pts.size() / 2]
				var s := 7.0 * _unit
				var tag := Rect2(mid - Vector2(s, s), Vector2(s, s) * 2.0)
				_link_layer.draw_rect(tag, Color(Palette.CARD, _link_fade))
				_link_layer.draw_rect(tag, colour, false, 2.0 * _unit)
				_link_layer.draw_line(mid - Vector2(s * 0.55, 0), mid + Vector2(s * 0.55, 0), colour, 2.2 * _unit)
				if link["sign"] >= 0.0:
					_link_layer.draw_line(mid - Vector2(0, s * 0.55), mid + Vector2(0, s * 0.55), colour, 2.2 * _unit)


func _dashes(pts: PackedVector2Array, colour: Color, width: float, dash: float, gap: float, phase: float) -> void:
	var period := dash + gap
	var walked := fposmod(-phase, period)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		var t := 0.0
		while t < length:
			var in_dash := fposmod(walked + t, period)
			var run := (dash - in_dash) if in_dash < dash else (period - in_dash)
			var stop := minf(length, t + run)
			if in_dash < dash:
				_link_layer.draw_line(a.lerp(b, t / length), a.lerp(b, stop / length), colour, width, true)
			t = stop + 0.001
		walked += length


func _draw_nodes() -> void:
	for key in order:
		var n: Dictionary = nodes[key]
		var a := _alpha(key)
		match n["kind"]:
			"policy":
				_draw_policy(n, a)
			"introduce":
				_draw_introduce(n, a)
			"indicator":
				_draw_indicator(n, a)
			"group":
				_draw_group(n, a)
			"centre":
				_draw_centre(n)
			"flag":
				_draw_flag(n)
	# Labels after every node, so no disc covers one.
	for key in order:
		_draw_label(nodes[key])


func _radius(n: Dictionary) -> float:
	return n["r"] * zoom * (1.0 + 0.06 * _lift.get(n["key"], 0.0)) * _appear.get(n["key"], 1.0)


func _icon(texture: Texture2D, c: Vector2, half: float, colour: Color) -> void:
	_node_layer.draw_texture_rect(texture, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false, colour)


func _draw_policy(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	var ink := Color(Palette.INK, a)
	var waiting: bool = n.get("waiting", 0) > 0
	if n.get("ghost", false):
		# Stage S13.5: a policy whose bill to introduce waits: a dashed outline on paper, its
		# pictogram faint, the setting proposed on the gauge and the waiting mark.
		_node_layer.draw_circle(c, r, Color(Palette.OCHRE.lerp(Palette.PAPER, 0.75), 0.85 * a))
		for k in 16:
			_node_layer.draw_arc(c, r, TAU * k / 16.0, TAU * (k + 0.55) / 16.0, 6, ink, maxf(2.0, 2.0 * _unit), true)
		_icon(n["icon"], c, r * 0.6, Color(Palette.INK, 0.45 * a))
		var m := c + Vector2(r * 0.72, -r * 0.72)
		_node_layer.draw_circle(m, 6.0 * _unit, Color(Palette.OCHRE, a))
		_node_layer.draw_arc(m, 6.0 * _unit, 0, TAU, 16, ink, 1.5, true)
		return
	_node_layer.draw_circle(c + Vector2(3, 3) * _unit, r, Color(Palette.SHADOW, 0.9 * a))
	_node_layer.draw_circle(c, r, Color(Palette.CARD, a) if not waiting else Color(Palette.OCHRE.lerp(Palette.CARD, 0.55), a))
	_node_layer.draw_arc(c, r, 0, TAU, 48, ink, maxf(2.0, 2.0 * _unit), true)
	if n["key"] == selected:
		_node_layer.draw_arc(c, r + 3.0 * _unit, 0, TAU, 48, Color(Palette.OCHRE, a), 3.0 * _unit, true)
	_icon(n["icon"], c, r * 0.6, ink)
	# The gauge: where the setting sits in its range, round the outside from the lower left.
	var gr := r + 6.0 * _unit * zoom ** 0.5
	var from := PI * 0.75
	var sweep := PI * 1.5
	_node_layer.draw_arc(c, gr, from, from + sweep, 40, Color(Palette.INK, 0.2 * a), 3.0 * _unit, true)
	var f: float = n["fraction"]
	if f >= 0.0:
		_node_layer.draw_arc(c, gr, from, from + sweep * maxf(f, 0.02), 40, Color(Palette.BLUE, a), 3.0 * _unit, true)
	var pf: float = n["pending"]
	if pf >= 0.0:
		var angle := from + sweep * pf
		var dir := Vector2(cos(angle), sin(angle))
		_node_layer.draw_line(c + dir * (gr - 6.0 * _unit), c + dir * (gr + 6.0 * _unit), Color(Palette.PENDING, a), 4.0 * _unit)
	if waiting:
		# A change waiting: an ochre mark at the top right.
		var m := c + Vector2(r * 0.72, -r * 0.72)
		_node_layer.draw_circle(m, 6.0 * _unit, Color(Palette.OCHRE, a))
		_node_layer.draw_arc(m, 6.0 * _unit, 0, TAU, 16, ink, 1.5, true)


## Stage S13.5: an area's "introduce a policy" node: a plus on card stock in the policies'
## style, with the number of policies there are to choose from on a small ochre badge.
func _draw_introduce(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	var ink := Color(Palette.INK, a)
	_node_layer.draw_circle(c + Vector2(2, 2) * _unit, r, Color(Palette.SHADOW, 0.5 * a))
	_node_layer.draw_circle(c, r, Color(Palette.PAPER.lerp(Palette.CARD, 0.5), a))
	for k in 12:
		_node_layer.draw_arc(c, r, TAU * k / 12.0, TAU * (k + 0.6) / 12.0, 6, ink, maxf(1.5, 1.5 * _unit), true)
	if n["key"] == hover or n["key"] == selected:
		_node_layer.draw_arc(c, r + 3.0 * _unit, 0, TAU, 48, Color(Palette.OCHRE, a), 3.0 * _unit, true)
	var arm := r * 0.5
	var w := maxf(3.0, r * 0.16)
	_node_layer.draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), ink, w)
	_node_layer.draw_line(c - Vector2(0, arm), c + Vector2(0, arm), ink, w)
	var count := int(n.get("count", 0))
	if count > 0:
		var m := c + Vector2(r * 0.78, -r * 0.78)
		var s := maxf(7.0, r * 0.42)
		_node_layer.draw_circle(m, s, Color(Palette.OCHRE, a))
		_node_layer.draw_arc(m, s, 0, TAU, 16, ink, 1.2, true)
		var font := Palette.text(600)
		var px := int(s * 1.3)
		var t := str(count)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		_node_layer.draw_string(font, m + Vector2(-tw / 2.0, px * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)


func _draw_indicator(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	_node_layer.draw_circle(c, r, Color(Palette.PAPER.lerp(Palette.CARD, 0.6), a))
	var band := maxf(3.0, r * 0.2)
	_node_layer.draw_arc(c, r - band / 2.0, 0, TAU, 48, Color(Palette.INK, a), band, true)
	if n["key"] == selected:
		_node_layer.draw_arc(c, r + 3.0 * _unit, 0, TAU, 48, Color(Palette.OCHRE, a), 3.0 * _unit, true)
	_icon(n["icon"], c, r * 0.5, Color(Palette.INK, a))
	_badge(n, c, r, a)


func _draw_group(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	var shield := PackedVector2Array()
	for p in [Vector2(-1, -0.9), Vector2(1, -0.9), Vector2(1, 0.1), Vector2(0.55, 0.7), Vector2(0, 1.0), Vector2(-0.55, 0.7), Vector2(-1, 0.1)]:
		shield.append(c + p * r)
	var shadow := PackedVector2Array()
	for p in shield:
		shadow.append(p + Vector2(3, 3) * _unit)
	_node_layer.draw_colored_polygon(shadow, Color(Palette.SHADOW, 0.9 * a))
	_node_layer.draw_colored_polygon(shield, Color(Palette.CARD, a))
	shield.append(shield[0])
	_node_layer.draw_polyline(shield, Color(Palette.INK, a), 2.0 * _unit, true)
	if n["key"] == selected:
		_node_layer.draw_polyline(shield, Color(Palette.OCHRE, a), 4.0 * _unit, true)
	_icon(n["icon"], c + Vector2(0, -r * 0.08), r * 0.55, Color(Palette.INK, a))
	# Stage S13.4: approval as a gauge round the shield, from the lower left, a full turn
	# being everyone; none for a group the governing party does not stand for.
	var gr := r * 1.12 + 5.0 * _unit * zoom ** 0.5
	var from := PI * 0.75
	var sweep := PI * 1.5
	_node_layer.draw_arc(c, gr, from, from + sweep, 40, Color(Palette.INK, 0.2 * a), 3.0 * _unit, true)
	var f: float = n.get("fraction", -1.0)
	if f > 0.0:
		_node_layer.draw_arc(c, gr, from, from + sweep * maxf(f, 0.02), 40, Color(Palette.SAGE, a), 3.0 * _unit, true)
	_badge(n, c, r, a)


## A node's rise or fall last month: a solid triangle on a small round badge at its upper
## right, sage or brick where the board says which way is better, ink where it does not.
func _badge(n: Dictionary, c: Vector2, r: float, a: float) -> void:
	var trend: int = n["trend"]
	if trend == 0:
		return
	var better := str(n["better"])
	var tone := Palette.INK
	if better != "":
		tone = Palette.GOOD if (trend > 0) == (better == "high") else Palette.BAD
	var m := c + Vector2(r * 0.74, -r * 0.74)
	var s := maxf(6.0, r * 0.3)
	_node_layer.draw_circle(m, s, Color(tone, a))
	var up := trend > 0
	var tri := PackedVector2Array([m + Vector2(0, -s * 0.55 if up else s * 0.55), m + Vector2(-s * 0.5, s * 0.35 if up else -s * 0.35),
		m + Vector2(s * 0.5, s * 0.35 if up else -s * 0.35)])
	_node_layer.draw_colored_polygon(tri, Color(Palette.CARD, a))


func _draw_centre(n: Dictionary) -> void:
	var c := to_screen(n["pos"])
	var r: float = n["r"] * zoom * (1.0 + 0.03 * _lift.get("centre", 0.0))
	_node_layer.draw_circle(c + Vector2(5, 5) * _unit, r, Palette.SHADOW)
	_node_layer.draw_circle(c, r, Palette.CARD)
	_node_layer.draw_arc(c, r, 0, TAU, 72, Palette.INK, 3.0 * _unit, true)
	_node_layer.draw_arc(c, r - 6.0 * _unit, 0, TAU, 72, Palette.INK, 1.0 * _unit, true)
	var display := Palette.display(500)
	var caps := Palette.display(600, 2)
	var body := Palette.text(500)
	var lines: Array = [
		[caps, centre.get("title", "APPROVAL"), int(maxf(13.0, r * 0.12)), Palette.MUTED, 0.0],
		[display, centre.get("figure", "–"), int(r * 0.4), Palette.INK, 0.0],
		[body, centre.get("change", ""), int(maxf(14.0, r * 0.125)), centre.get("change_colour", Palette.MUTED), 0.0],
		[body, centre.get("election", ""), int(maxf(14.0, r * 0.125)), Palette.INK, 0.0],
		[body, centre.get("capital", ""), int(maxf(14.0, r * 0.125)), centre.get("capital_colour", Palette.INK), 0.0],
	]
	var total := 0.0
	for line in lines:
		if str(line[1]) != "":
			total += line[2] * 1.18
	var y := c.y - total / 2.0
	for line in lines:
		if str(line[1]) == "":
			continue
		var f: Font = line[0]
		var size_px: int = line[2]
		var w := f.get_string_size(str(line[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		if w > r * 1.6:  # stage S13.4: a smaller medallion; a line too wide for it is set smaller
			size_px = int(size_px * r * 1.6 / w)
			w = f.get_string_size(str(line[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		y += size_px * 1.18
		_node_layer.draw_string(f, Vector2(c.x - w / 2.0, y - size_px * 0.22), str(line[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, line[3])


func _draw_flag(n: Dictionary) -> void:
	var hit: Rect2 = n["hit"]
	var rect := Rect2(to_screen(hit.position), hit.size * zoom)
	var tone := str(n.get("tone", "plain"))
	var colour: Color = {"good": Palette.SAGE, "bad": Palette.BRICK, "ask": Palette.OCHRE}.get(tone, Palette.CARD_DEEP)
	var ink := Palette.CARD if tone in ["good", "bad"] else Palette.INK
	# A pennant: a staff on the left, the cloth notched on the right.
	var notch := rect.size.y * 0.3
	var cloth := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - notch, rect.get_center().y),
		Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)])
	var shadow := PackedVector2Array()
	for p in cloth:
		shadow.append(p + Vector2(3, 3) * _unit)
	_node_layer.draw_colored_polygon(shadow, Palette.SHADOW)
	_node_layer.draw_colored_polygon(cloth, colour)
	cloth.append(cloth[0])
	_node_layer.draw_polyline(cloth, Palette.INK, 1.5 * _unit, true)
	if n["key"] == hover:
		_node_layer.draw_polyline(cloth, Palette.INK, 3.0 * _unit, true)
	var size_px := int(roundf(clampf(14.0 * _unit, 14.0, 20.0) * sqrt(zoom)))
	var font := Palette.text(600 if tone == "ask" else 500)
	_node_layer.draw_string(font, Vector2(rect.position.x + 10.0 * _unit, rect.get_center().y + size_px * 0.36), str(n["label"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, ink)
	if n["key"] == hover and str(n.get("value", "")) != str(n["label"]):
		# Pointed at: the whole of it (since when) on a tag above the flag.
		var body := Palette.text(500)
		var words := str(n["value"])
		var w := body.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var box := Rect2(rect.get_center().x - w / 2.0 - 8.0, rect.position.y - size_px - 18.0, w + 16.0, size_px + 12.0)
		_node_layer.draw_rect(Rect2(box.position + Vector2(3, 3), box.size), Palette.SHADOW)
		_node_layer.draw_rect(box, Palette.CARD)
		_node_layer.draw_rect(box, Palette.INK, false, 1.5)
		_node_layer.draw_string(body, Vector2(box.position.x + 8.0, box.end.y - 7.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Palette.INK)


func _draw_label(n: Dictionary) -> void:
	if n["kind"] in ["centre", "flag"] or (n["label_rect"] as Rect2).size == Vector2.ZERO:
		return
	var key: String = n["key"]
	var focus := focus_key()
	var linked := false
	for link in _links:
		if link["from"] == key or link["to"] == key:
			linked = true
	var tier: int = n["tier"]
	var shown: bool = n.get("rest", false) or zoom >= (1.45 if tier >= 2 else 1.9) or key == hover or key == selected or linked
	if not shown:
		return
	var a := _alpha(key)
	var font := Palette.display(500)
	var size_px := int(roundf(node_label_size(n) * clampf(sqrt(zoom), 1.0, 1.35)))
	var rect: Rect2 = n["label_rect"]
	var centre_at := to_screen(rect.get_center())
	var lines: PackedStringArray = n.get("lines", PackedStringArray([n["label"]]))
	var detail := ""
	if key == focus and str(n.get("value", "")) != "":
		detail = str(n["value"]) + (("  " + str(n["change"])) if str(n.get("change", "")) != "" else "")
	# Stage S13.4: a group's approval on a line under its name.
	var figure := str(n.get("value", "")) if n["kind"] == "group" and detail == "" else ""
	var h := lines.size() * (size_px + 2.0) + (size_px + 2.0 if figure != "" else 0.0)
	var y := centre_at.y - h / 2.0
	if key == focus:
		# The focused node's label sits on a tag of card stock, with its value under it.
		var w := 0.0
		for line in lines:
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
		var dsize := int(size_px * 0.95)
		var body := Palette.text(500)
		if detail != "":
			w = maxf(w, body.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, dsize).x)
		var box := Rect2(centre_at.x - w / 2.0 - 8.0, y - 5.0, w + 16.0, h + (dsize + 4.0 if detail != "" else 0.0) + 10.0)
		_node_layer.draw_rect(Rect2(box.position + Vector2(3, 3), box.size), Palette.SHADOW)
		_node_layer.draw_rect(box, Palette.CARD)
		_node_layer.draw_rect(box, Palette.INK, false, 1.5)
		if detail != "":
			var dw := body.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, dsize).x
			_node_layer.draw_string(body, Vector2(centre_at.x - dw / 2.0, y + h + dsize * 0.95), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, dsize, Palette.MUTED)
	var texts: Array = Array(lines).map(func(line): return [line, font, Palette.INK])
	if figure != "":
		texts.append([figure, Palette.text(600), Palette.INK])
	for item in texts:
		var f: Font = item[1]
		var w := f.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		y += size_px + 2.0
		var at := Vector2(centre_at.x - w / 2.0, y - size_px * 0.25)
		if key != focus:
			_node_layer.draw_string_outline(f, at, item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 6, Color(Palette.PAPER, 0.9 * a))
		_node_layer.draw_string(f, at, item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(item[2], a))


func _draw_effects() -> void:
	for key in _pulses:
		if not nodes.has(key):
			continue
		var n: Dictionary = nodes[key]
		var t: float = _pulses[key]
		for k in 2:
			var phase := t - k * 0.35
			if phase < 0.0 or phase > 1.0:
				continue
			var r: float = n["r"] * zoom + (6.0 + 22.0 * phase) * _unit
			_fx_layer.draw_arc(to_screen(n["pos"]), r, 0, TAU, 48, Color(Palette.OCHRE, (1.0 - phase) * 0.8), 2.5 * _unit, true)
