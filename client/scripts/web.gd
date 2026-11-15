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

const Palette := preload("res://scripts/palette.gd")

signal node_pressed(key: String)
signal hover_changed(key: String)

## Node radius by tier, in pixels at a unit scale of 1.
const RADIUS := [0.0, 17.0, 22.0, 29.0]
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.0
## Links shown for a policy: the strongest few, above a small threshold.
const MAX_LINKS := 8
const LINK_FLOOR := 0.0005

var fmt: RefCounted
## key -> node: {key, kind ("policy", "indicator", "group", "flag", "centre"), label, icon,
## tier, area, levers, row, name (catalogue entry), better, doc, pos, r, label_rect, ...}
var nodes := {}
var order: PackedStringArray = []  # node keys in drawing order
var areas: Array = []  # {name, icon, policies: [key], indicators: [key], from, to (polar angles)}
var hidden_levers: PackedStringArray = []  # levers the board leaves out
var groups: Array = []  # [play.web] groups
## Measured effects a year on, from the bridge: lever -> {row: signed strength}.
var effects := {}
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
var _c := Vector2.ZERO
var _rim: Array = []  # [glyph, position, angle, rect] for the area names along the rim
var _arcs: Array = []  # per area, the rim arc's points
var _guides: Array = []  # the rings' outlines, as points
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
	resized.connect(layout)


# ---------------------------------------------------------------------------- building

## Builds the board from the catalogue (name -> entry), the scenario's [play] table and the
## player's levers. `label_of` gives a result row's label as the screen shows it.
func build(entries: Dictionary, play: Dictionary, levers: Array, label_of: Callable) -> void:
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
			for i in area.get("indicators", []):
				var row := str(i.get("row", ""))
				if not rows.has(row.trim_prefix("-")):
					continue
				var key := "indicator:" + row
				_add(key, "indicator", label_of.call(row), str(i.get("icon", "")), int(i.get("size", 2)), a["name"],
					PackedStringArray(), row, rows[row.trim_prefix("-")], str(i.get("better", "")))
				a["indicators"].append(key)
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
				home = {"name": group, "icon": "", "policies": [], "indicators": []}
				areas.append(home)
			var key := "policy:" + lever
			_add(key, "policy", str(entry.get("label", lever)), "", 2, group, PackedStringArray([lever]), "", lever)
			home["policies"].append(key)
	else:
		_automatic(entries, play, levers, rows, label_of)
	for g in groups:
		var row := str(g.get("row", ""))
		if not rows.has(row):
			continue
		_add("group:" + str(g.get("key", row)), "group", str(g.get("label", row)), str(g.get("icon", "group")), 2, "",
			PackedStringArray(), row, rows[row], "high")
		nodes["group:" + str(g.get("key", row))]["share"] = str(g.get("share", ""))
	_add("centre", "centre", "Government", "vote", 3, "", PackedStringArray(), "", "", "")
	selected = ""
	hover = ""
	layout()


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
	var stagger := (RADIUS[3] * 2.0 + 10.0) * u
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
			p += (2.0 * RADIUS[nodes[key]["tier"]] + 24.0) * u
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
	var rim := Ring.new(_c, outer.rx + RADIUS[3] * u + 16.0 * u, outer.ry + RADIUS[3] * u + 12.0 * u)
	_arcs.clear()
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
	# Interest groups on a ring round the centre; the centre itself.
	var centre_r := clampf(minf(inner.ry, middle.ry) * 0.62, 70.0 * u, 128.0 * u)
	nodes["centre"]["pos"] = _c
	nodes["centre"]["r"] = centre_r
	var group_keys := keys_of_unordered("group")
	if not group_keys.is_empty():
		var ring := Ring.new(_c, centre_r + (inner.rx - centre_r) * 0.45, centre_r + (inner.ry - centre_r) * 0.55)
		_place_row(group_keys, ring, 0.0, 1.0)
	_guides = [_outline(outer), _outline(middle)]
	_order_nodes()
	_place_labels()
	set_flags(_flags)
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
		node["r"] = RADIUS[node["tier"]] * _unit


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
	var arc := PackedVector2Array()
	for i in 61:
		arc.append(ring.at(lerpf(fa, fb, i / 60.0)))
	_arcs.append(arc)
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
	for kind in ["centre", "group", "indicator", "policy", "flag"]:
		for key in nodes:
			if nodes[key]["kind"] == kind:
				order.append(key)


## Labels for the largest nodes: below, above, inside or outside the node, whichever first
## clears every node, the rim and the labels already placed.
func _place_labels() -> void:
	var placed: Array = []
	var font := Palette.display(500)
	var size_px := label_size()
	for key in order:
		var node: Dictionary = nodes[key]
		node["label_rect"] = Rect2()
		if node["kind"] in ["centre", "flag"]:
			continue
		var best := Rect2()
		var first := Rect2()
		# A wide label first, then a narrower one on two lines; each tried round the node.
		for width in [130.0, 84.0]:
			var lines := wrap_label(str(node["label"]), font, size_px, width * _unit)
			var w := 0.0
			for line in lines:
				w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
			var h := lines.size() * (size_px + 2.0)
			var p: Vector2 = node["pos"]
			var r: float = node["r"] + 6.0 * _unit
			var inward := (_c - p).normalized()
			var below := Vector2(0, r + h / 2.0 + 2.0)
			var above := Vector2(0, -r - h / 2.0 - 2.0)
			var side := Vector2((r + w / 2.0 + 4.0) * signf(inward.x), 0)
			var lean := Vector2((w / 2.0) * signf(inward.x), 0)
			# Policies label towards the centre, clear of the rim; indicators below, then above.
			var candidates := [below, above, side, -side, below + lean, above + lean, below - lean, above - lean]
			if node["kind"] == "policy":
				candidates = [above if inward.y < 0.0 else below, side if absf(inward.x) > 0.75 else below] + candidates
			for offset in candidates:
				var rect := Rect2(p + offset - Vector2(w, h) / 2.0, Vector2(w, h))
				if first.size == Vector2.ZERO:
					first = rect
					node["lines"] = lines
				if _clear(rect, key, placed):
					best = rect
					node["lines"] = lines
					break
			if best.size != Vector2.ZERO:
				break
		if best.size == Vector2.ZERO:
			best = first
			node["lines"] = wrap_label(str(node["label"]), font, size_px, 130.0 * _unit)
		node["label_rect"] = best
		if node["tier"] == 3:
			placed.append(best)


func _clear(rect: Rect2, own: String, placed: Array) -> bool:
	if not Rect2(Vector2.ZERO, size).encloses(rect):
		return false
	for key in nodes:
		if key == own:
			continue
		var n: Dictionary = nodes[key]
		if _rect_circle(rect, n["pos"], n["r"] + 3.0 * _unit):
			return false
	for r in placed:
		if (r as Rect2).grow(2.0).intersects(rect):
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
		if a["tier"] == 3 and a["label_rect"].size != Vector2.ZERO:
			for j in keys.size():
				if j == i:
					continue
				var b: Dictionary = nodes[keys[j]]
				if _rect_circle(a["label_rect"], b["pos"], b["r"]):
					out.append("label of %s and %s" % [keys[i], keys[j]])
				if b["tier"] == 3 and j > i and b["label_rect"].size != Vector2.ZERO and (a["label_rect"] as Rect2).intersects(b["label_rect"]):
					out.append("labels of %s and %s" % [keys[i], keys[j]])
		if a["kind"] == "flag":
			for j in keys.size():
				var b: Dictionary = nodes[keys[j]]
				if b["kind"] != "flag" and _rect_circle(a["hit"], b["pos"], b["r"]):
					out.append("flag %s and %s" % [keys[i], keys[j]])
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
		var r: float = n["r"] * zoom * (1.0 + 0.06 * _lift.get(key, 0.0)) + 4.0
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
			set_hover(node_at(event.position))
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


## Points at a node (the pointer's, or a script's): lifts it and shows its links.
func set_hover(key: String) -> void:
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


## New measured effects arrived: the links shown are worked out again.
func effects_changed() -> void:
	_reach.clear()
	_link_key = "-"
	_focus_changed()


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
	if node["kind"] == "policy":
		var best := {}  # target key -> [signed strength, measured]
		# A policy of several levers is measured by its first, the one its gauge shows (the
		# basic rate for Income tax), so a link's direction always means "raising this".
		for lever in (node["levers"] as PackedStringArray).slice(0, 1):
			if effects.has(lever):
				for row in effects[lever]:
					var target := _target_of_row(row, targets)
					if target == "":
						continue
					var s := float(effects[lever][row])
					if absf(s) >= LINK_FLOOR and (not best.has(target) or absf(s) > absf(best[target][0])):
						best[target] = [s, true]
		if best.is_empty():
			var shown := {}
			for t in targets:
				shown[nodes[t]["name"]] = t
			for lever in node["levers"]:
				for name in _cached_reach(lever, shown):
					best[shown[name]] = [0.0, false]
		var ranked := best.keys()
		ranked.sort_custom(func(a, b): return absf(best[a][0]) > absf(best[b][0]))
		var top := 1e-12
		for t in ranked:
			top = maxf(top, absf(best[t][0]))
		for t in ranked.slice(0, MAX_LINKS):
			out.append({"from": key, "to": t, "sign": signf(best[t][0]), "strength": absf(best[t][0]) / top if best[t][1] else 0.35,
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
		var control := mid + normal * pa.distance_to(pb) * 0.22
		var start: Vector2 = pa + (control - pa).normalized() * (a["r"] + 3.0 * _unit)
		var end: Vector2 = pb + (control - pb).normalized() * (b["r"] + 7.0 * _unit)
		var points := PackedVector2Array()
		for i in 25:
			var t := i / 24.0
			points.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
		link["points"] = points


# ---------------------------------------------------------------------------- refresh

## Each node's state from the game: `value_of(row)` and `before_of(row)` read result rows
## (a "-" in front negates), `lever_of(name)` a lever's setting and `start_of(name)` where it
## began, `pending` the changes waiting. Nodes that moved notably pulse.
func refresh(value_of: Callable, before_of: Callable, lever_of: Callable, start_of: Callable, pending: Dictionary, pulse := false) -> void:
	for key in nodes:
		var n: Dictionary = nodes[key]
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
		elif n["kind"] in ["indicator", "group"]:
			var entry: Dictionary = _entries.get(n["name"], {})
			var now: Variant = value_of.call(n["row"])
			var was: Variant = before_of.call(n["row"])
			n["value"] = fmt.value(entry, now, true, false) if fmt != null else ""
			n["trend"] = 0
			n["change"] = ""
			if now != null and was != null and typeof(now) != TYPE_BOOL:
				var d := float(now) - float(was)
				var scale := maxf(absf(float(was)), 1e-9)
				var notable := absf(d) * 100.0 >= 0.1 if fmt != null and fmt.is_rate(entry) else absf(d) / scale >= 0.005
				n["trend"] = 0 if d == 0.0 else (1 if d > 0.0 else -1)
				n["change"] = fmt.change(entry, d) if fmt != null else ""
				if pulse and notable:
					_pulses[key] = 0.0
	if not _pulses.is_empty():
		set_process(true)
	queue_layers()


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
func set_flags(flags: Array) -> void:
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
	# column to its left (right-aligned to it), a second to its right.
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
		var key := "flag:" + str(f["key"])
		_add(key, "flag", str(f["text"]), "", 1, "", PackedStringArray(), str(f.get("row", "")), str(f.get("name", "")))
		nodes[key]["tone"] = str(f.get("tone", "plain"))
		nodes[key]["value"] = str(f["text"]) + str(f.get("since", ""))
		nodes[key]["doc"] = str(f.get("doc", ""))
		nodes[key]["hit"] = Rect2(x, y, w, h)
		nodes[key]["pos"] = (nodes[key]["hit"] as Rect2).get_center()
		nodes[key]["r"] = 0.0
	_order_nodes()
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
	for arc in _arcs:
		var pts := PackedVector2Array()
		for p in arc:
			pts.append(to_screen(p))
		if pts.size() > 1:
			_base.draw_polyline(pts, Color(Palette.INK, 0.55), 1.5, true)
			for end in [0, pts.size() - 1]:
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
		var width := (1.5 + 4.0 * float(link["strength"])) * sqrt(zoom) * _unit
		# A faint full line under flowing dashes; the dashes run faster for a stronger link.
		_link_layer.draw_polyline(pts, Color(colour, 0.28), width, true)
		_dashes(pts, colour, width, 14.0 * _unit, 9.0 * _unit, _flow * (30.0 + 50.0 * float(link["strength"])) * _unit)
		if _draw_in >= 1.0:
			var tip := pts[pts.size() - 1]
			var dir := (tip - pts[pts.size() - 3]).normalized()
			var side := dir.orthogonal()
			var head := (8.0 + width * 1.4)
			_link_layer.draw_colored_polygon(PackedVector2Array([tip, tip - dir * head + side * head * 0.55, tip - dir * head - side * head * 0.55]), colour)
			if link["measured"]:
				# The direction as a glyph as well as a colour: a triangle up or down mid-way.
				var mid := pts[pts.size() / 2]
				var s := 7.0 * _unit
				_link_layer.draw_circle(mid, s * 1.5, Palette.CARD)
				_link_layer.draw_arc(mid, s * 1.5, 0, TAU, 20, colour, 1.5, true)
				var up: bool = link["sign"] >= 0.0
				var tri := PackedVector2Array([mid + Vector2(0, -s if up else s) * 0.8, mid + Vector2(-s * 0.8, s * 0.6 if up else -s * 0.6),
					mid + Vector2(s * 0.8, s * 0.6 if up else -s * 0.6)])
				_link_layer.draw_colored_polygon(tri, colour)


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
	return n["r"] * zoom * (1.0 + 0.06 * _lift.get(n["key"], 0.0))


func _icon(texture: Texture2D, c: Vector2, half: float, colour: Color) -> void:
	_node_layer.draw_texture_rect(texture, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false, colour)


func _draw_policy(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	var ink := Color(Palette.INK, a)
	var waiting: bool = n.get("waiting", 0) > 0
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


func _draw_indicator(n: Dictionary, a: float) -> void:
	var c := to_screen(n["pos"])
	var r := _radius(n)
	var tone := Palette.INK
	var trend: int = n["trend"]
	var better := str(n["better"])
	if trend != 0 and better != "":
		tone = Palette.GOOD if (trend > 0) == (better == "high") else Palette.BAD
	_node_layer.draw_circle(c, r, Color(Palette.PAPER.lerp(Palette.CARD, 0.6), a))
	var band := maxf(3.0, r * 0.2)
	_node_layer.draw_arc(c, r - band / 2.0, 0, TAU, 48, Color(Palette.INK, a), band, true)
	if n["key"] == selected:
		_node_layer.draw_arc(c, r + 3.0 * _unit, 0, TAU, 48, Color(Palette.OCHRE, a), 3.0 * _unit, true)
	_icon(n["icon"], c, r * 0.5, Color(Palette.INK, a))
	if trend != 0:
		# Rose or fell last month: a solid triangle on a small disc at the upper right.
		var m := c + Vector2(r * 0.74, -r * 0.74)
		var s := maxf(6.0, r * 0.3)
		_node_layer.draw_circle(m, s, Color(tone if better != "" else Palette.INK, a))
		var up := trend > 0
		var tri := PackedVector2Array([m + Vector2(0, -s * 0.55 if up else s * 0.55), m + Vector2(-s * 0.5, s * 0.35 if up else -s * 0.35),
			m + Vector2(s * 0.5, s * 0.35 if up else -s * 0.35)])
		_node_layer.draw_colored_polygon(tri, Color(Palette.CARD, a))


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
	_icon(n["icon"], c + Vector2(0, -r * 0.05), r * 0.5, Color(Palette.INK, a))


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
	var shown := tier == 3 or zoom >= (1.45 if tier == 2 else 1.9) or key == hover or key == selected or linked
	if not shown:
		return
	var a := _alpha(key)
	var font := Palette.display(500)
	var size_px := int(roundf(label_size() * clampf(sqrt(zoom), 1.0, 1.35)))
	var rect: Rect2 = n["label_rect"]
	var centre_at := to_screen(rect.get_center())
	var lines: PackedStringArray = n.get("lines", PackedStringArray([n["label"]]))
	var detail := ""
	if key == focus and str(n.get("value", "")) != "":
		detail = str(n["value"]) + (("  " + str(n["change"])) if str(n.get("change", "")) != "" else "")
	var h := lines.size() * (size_px + 2.0)
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
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		y += size_px + 2.0
		if key != focus:
			_node_layer.draw_string_outline(font, Vector2(centre_at.x - w / 2.0, y - size_px * 0.25), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 6, Color(Palette.PAPER, 0.9 * a))
		_node_layer.draw_string(font, Vector2(centre_at.x - w / 2.0, y - size_px * 0.25), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(Palette.INK, a))


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
