extends VBoxContainer
## Stage S14.1: the key, one page: what each shape, colour and arc on the board means. Every
## sample is drawn by the board's own code (a small board in demo mode, web.gd, and the
## strip's pennants, strip.gd), so the key cannot drift from the board.

const Palette := preload("res://scripts/palette.gd")
const Web := preload("res://scripts/web.gd")
const Strip := preload("res://scripts/strip.gd")

const SAMPLE := Vector2(250, 84)


## `board` gives the scenario's thresholds for approval.
func build(board: Web) -> void:
	add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	Palette.rule_rows(grid)
	add_child(grid)
	_row(grid, _policies(), "Policies", "Round the rim, by area. The arc round a disc is where the policy stands in its range; an ochre mark is a change waiting for next month. A dashed disc is a policy waiting to be introduced; Add policy, on the top bar, lists those not in force.")
	_row(grid, _indicators(), "Indicators", "The figures you are judged by. Green: a good thing, the more the better; red: a bad thing, the less the better; blue: neither. The small triangle: last month's rise or fall, green when for the better, red when for the worse.")
	_row(grid, _groups(board), "Groups of voters", "One circle round the centre, in %s, each named once inside it. An arc is as long as the group's share of its family. Outside it, its approval as a gauge, full at %d%%: green from %d%%, mustard between, red under %d%%; grey with no figure.%s" % [
		_families_word(board), roundi(Web.APPROVAL_FULL * 100.0), roundi(board.approval_good * 100.0), roundi(board.approval_bad * 100.0),
		" Groups of belief answer to where the government stands, not how they are doing: Parliament shows the stances." if not board.play_web.get("stances", []).is_empty() else ""])
	_row(grid, _links(), "Links", "Point at a node for what it moves, or what moves it, in a year. Green: good for what it reaches; red: bad; blue: neither can be said; grey: not yet measured. Thicker is stronger; + it rises, − it falls.")
	_row(grid, _flags(), "Situations", "On the strip under the top bar, and as a small flag on the statistic that set it off: green a good situation, red a bad one; blue an answer you gave, in force; ochre, a question waiting for your answer. Click one to light its statistic and see why.")
	var last := Label.new()
	last.text = "A bigger node matters more. At the centre: approval, the months to the election and your political capital."
	last.theme_type_variation = "Muted"
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	last.custom_minimum_size.x = 600.0
	add_child(last)


## "seven families", as many as the board has.
static func _families_word(board: Web) -> String:
	var seen := {}
	for k in board.keys_of("group"):
		seen[board.nodes[k]["family"]] = true
	var words := ["no families", "one family", "two families", "three families", "four families", "five families", "six families", "seven families", "eight families", "nine families"]
	return words[seen.size()] if seen.size() < words.size() else "%d families" % seen.size()


func _row(grid: GridContainer, sample: Control, heading: String, words: String) -> void:
	grid.add_child(sample)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(Palette.caps(heading))
	var text := Label.new()
	text.text = words
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 380.0
	box.add_child(text)
	grid.add_child(box)


## A node as the board holds one, at `pos` with radius `r`, with `extra` fields.
static func _node(key: String, kind: String, icon: String, pos: Vector2, r: float, extra := {}) -> Dictionary:
	var n := {"key": key, "kind": kind, "label": "", "tier": 2, "area": "", "levers": PackedStringArray(), "row": "", "name": "",
		"better": "", "doc": "", "icon": Palette.icon(icon), "pos": pos, "r": r, "label_rect": Rect2(), "fraction": -1.0,
		"pending": -1.0, "trend": 0, "value": "", "change": "", "state": "steady"}
	n.merge(extra, true)
	return n


func _board(items: Array, height := SAMPLE.y) -> Web:
	var web := Web.new()
	web.demo = true
	web.custom_minimum_size = Vector2(SAMPLE.x, height)
	web.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in items:
		web.nodes[n["key"]] = n
		web.order.append(n["key"])
	return web


func _policies() -> Control:
	return _board([
		_node("a", "policy", "income-tax", Vector2(34, 42), 22.0, {"fraction": 0.55}),
		_node("b", "policy", "vat", Vector2(98, 42), 22.0, {"fraction": 0.4, "pending": 0.7, "waiting": 1}),
		_node("c", "policy", "policy", Vector2(162, 42), 22.0, {"ghost": true}),
	])


func _indicators() -> Control:
	return _board([
		_node("a", "indicator", "gdp", Vector2(34, 42), 22.0, {"state": "steady"}),
		_node("b", "indicator", "jobs", Vector2(98, 42), 22.0, {"state": "better", "trend": 1, "better": "high"}),
		_node("c", "indicator", "prices", Vector2(162, 42), 22.0, {"state": "worse", "trend": 1, "better": "low"}),
	])


func _groups(board: Web) -> Control:
	var web := _board([], 92.0)
	web._unit = 1.0
	web._group_band = Web.RING_BAND
	web._group_ring = Web.Ring.new(Vector2(SAMPLE.x / 2.0, 250.0), 230.0, 230.0)
	var ring: Web.Ring = web._group_ring
	var length := ring.length()
	var specs := [["group-young", "good", board.approval_good + 0.08], ["group-parents", "mixed", (board.approval_good + board.approval_bad) / 2.0],
		["pensioner", "bad", board.approval_bad - 0.06], ["group-patriots", "none", -1.0]]
	var f := -(4 * 52.0 + 3 * 4.0) / 2.0 / length
	for i in specs.size():
		var f1 := f + 52.0 / length
		var n := _node(str(i), "group", specs[i][0], ring.at((f + f1) / 2.0), Web.RING_BAND * 0.45,
			{"f0": f, "f1": f1, "seg_len": 52.0, "state": specs[i][1], "fraction": specs[i][2]})
		web.nodes[n["key"]] = n
		web.order.append(n["key"])
		n["band_poly"] = web._band_polygon(f, f1, Web.RING_BAND / 2.0)
		n["track"] = ring.path(f, f1, Web.RING_BAND / 2.0 + Web.ARC_OFFSET + Web.ARC_WIDTH / 2.0, 3.0)
		f = f1 + 4.0 / length
	return web


func _links() -> Control:
	var items := []
	var links := []
	var specs := [["better", 1.0, "high"], ["worse", -1.0, "high"], ["steady", 1.0, ""]]
	for i in specs.size():
		var y := 16.0 + i * 34.0
		items.append(_node("p%d" % i, "policy", "policy", Vector2(20, y), 11.0, {"fraction": 0.5}))
		items.append(_node("i%d" % i, "indicator", "gdp", Vector2(226, y), 11.0, {"better": specs[i][2]}))
		links.append({"from": "p%d" % i, "to": "i%d" % i, "sign": specs[i][1], "strength": 0.3 + 0.3 * i, "measured": true})
	var web := _board(items, 104.0)
	web.ready.connect(func() -> void:
		web._set_links(links)
		for link in web._links:  # a gentle bow, so each stays in its own row
			var a: Dictionary = web.nodes[link["from"]]
			var b: Dictionary = web.nodes[link["to"]]
			link["points"] = web._curve(a, b, (a["pos"] + b["pos"]) / 2.0 + Vector2(0, -9)))
	return web


func _flags() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = SAMPLE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	for pair in [[["good", "Boom"], ["bad", "Recession"]], [["plain", "An answer"], ["ask", "Decide"]]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)
		for spec in pair:
			var pennant := Strip.Pennant.new()
			pennant.flag = {"key": spec[1], "text": spec[1], "tone": spec[0]}
			pennant.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(pennant)
	return row
