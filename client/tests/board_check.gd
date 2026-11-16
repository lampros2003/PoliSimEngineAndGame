extends SceneTree
## Stage S13.2: the board, through the interface (models/uk/scenarios/2025.toml). The UK
## board is built from [play.web]: ten areas, 24 policies (stage S13.6: at least, as many as
## the table places) holding every lever the player
## has but Scotland's own income tax, 24 indicators; no two nodes, and no label shown at
## rest, nor four situation flags, overlap at 1366x768, 1920x1080 or 2560x1440; every node opens the right popup (the
## centre, Parliament); a basic rate typed in Income tax's popup waits with its cost in
## political capital; pointing at a policy shows its links; the Budget's lines open their
## popups. Then models/mini, which has no [play.web], gets an automatic board. Stage S13.4:
## the 18 interest groups round the centre in their five families, each family together;
## a label at rest for most nodes, none touching another node, label or flag at the three
## sizes; a group opens a group popup; models/mini's board has an empty middle. Stage S13.6:
## every node labelled at rest at 1920x1080 and 2560x1440, at least 95% at 1366x768; no
## hover link passes under the centre medallion. Stage S13.5: exact counts from [play.web]:
## the policies in force on the board, those not in force kept off it and counted on their
## areas' introduce nodes, the indicators, and 23 groups in six families (the estimated
## groups' "Ways of life" last); every lever is on the board or available to introduce; at
## least 90% of nodes labelled at 1366x768. Stage S14.1: the board is the screen: the 23
## groups are arcs of one ring, in family order, none running into the next or too short for
## its pictogram, at the three sizes; every policy and indicator labelled at rest at all three
## (the groups only where they fit); nothing in the ring; a drag and a wheel move no node; an
## indicator's colour follows its `better`. Stage S14.4: the group ring a circle, its names
## all at rest or none; no label on the rim's names.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	if main.failed:
		return _fail("the game did not start")
	var board = main.board
	if not board.authored or board.areas.size() != 10:
		return _fail("the board has %d areas (authored: %s)" % [board.areas.size(), board.authored])
	var policies: int = board.keys_of("policy").size()
	var indicators: int = board.keys_of("indicator").size()
	# Stage S13.5: exactly what [play.web] places: a policy with `off` whose lever stands
	# there is not in force, off the board and counted on its area's introduce node.
	var want_policies := 0
	var want_available := 0
	var want_indicators := 0
	var want_introduce := 0
	for area in main.play["web"]["areas"]:
		var spare := 0
		for p in area.get("policies", []):
			if Array(p.get("levers", [])).any(func(l): return main.entries.has(str(l)) and main.entries[str(l)].get("player", true)):
				var lever := str(p["levers"][0])
				var stored: float = float(p.get("off", 0.0)) * (main.fmt.minor if main.entries[lever].get("money", false) else 1)
				if p.has("off") and absf(float(main.game.latest(lever)) - stored) < 1e-6:
					spare += 1
				else:
					want_policies += 1
		for i in area.get("indicators", []):
			if main.rows.has(str(i.get("row", "")).trim_prefix("-")):
				want_indicators += 1
		want_available += spare
		want_introduce += 1 if spare > 0 else 0
		var node: Dictionary = board.nodes.get("introduce:" + str(area["name"]), {})
		if (spare > 0) == node.is_empty() or (spare > 0 and int(node["count"]) != spare) or main.available_policies(str(area["name"])).size() != spare:
			return _fail("%s: %d policies not in force, its introduce node %s" % [area["name"], spare, node.get("count", "missing")])
	if policies != want_policies or board.available.size() != want_available or board.keys_of("introduce").size() != want_introduce \
			or indicators != want_indicators or policies < 38 or want_available < 5 or indicators < 33:
		return _fail("the board has %d policies in force, %d available, %d introduce nodes and %d indicators; [play.web] %d, %d, %d and %d" % [
			policies, board.available.size(), board.keys_of("introduce").size(), indicators, want_policies, want_available, want_introduce, want_indicators])
	var families := []
	for key in board.keys_of("group"):
		var family := str(board.nodes[key]["family"])
		if families.is_empty() or families[-1] != family:
			families.append(family)
	if board.keys_of("group").size() != 23 or families != ["Ages", "Incomes", "Work", "Families", "Places", "Ways of life"]:
		return _fail("the groups: %d in families %s" % [board.keys_of("group").size(), families])
	var on_board: PackedStringArray = main.board_levers()
	for key in board.available:
		on_board.append_array(board.available[key]["levers"])
	for name in main.entries:
		var entry: Dictionary = main.entries[name]
		if entry["kind"] != "lever" or not entry.get("player", true):
			continue
		var scottish := str(entry.get("group", "")) == "Scottish income tax"
		if on_board.has(name) == scottish:
			return _fail("%s is %s the board" % [name, "on" if scottish else "neither on nor available to"])
	var own_size: Vector2 = board.size
	var rested := []
	for view in [Vector2(1366, 768), Vector2(1920, 1080), Vector2(2560, 1440)]:
		board.size = view - Vector2(0, main.BAR_HEIGHT + main.STRIP_HEIGHT)
		board.layout()
		var found: PackedStringArray = board.overlaps()
		if not found.is_empty():
			return _fail("at %dx%d: %s" % [view.x, view.y, ", ".join(found)])
		var labelled := 0
		var labels := 0
		var groups_labelled := 0
		for key in board.order:
			var kind: String = board.nodes[key]["kind"]
			if kind == "group":
				groups_labelled += 1 if board.nodes[key]["rest"] else 0
			elif kind != "centre":
				labels += 1
				labelled += 1 if board.nodes[key]["rest"] else 0
		# Stage S14.4: the groups' ring is a circle; its names all at rest or none.
		if not is_equal_approx(board._group_ring.rx, board._group_ring.ry):
			return _fail("at %dx%d the group ring is not a circle" % [view.x, view.y])
		if groups_labelled != 0 and groups_labelled != board.keys_of("group").size():
			return _fail("at %dx%d %d of the groups are labelled at rest" % [view.x, view.y, groups_labelled])
		if labelled != labels:
			var missing := Array(board.order).filter(func(k): return not board.nodes[k]["kind"] in ["centre", "group"] and not board.nodes[k]["rest"])
			return _fail("at %dx%d only %d of %d nodes are labelled at rest: not %s" % [view.x, view.y, labelled, labels, missing])
		rested.append("%d of %d and %d groups at %dx%d" % [labelled, labels, groups_labelled, view.x, view.y])
	board.size = own_size
	board.layout()
	# The board cannot be moved: a drag across it and the wheel leave every node where it was.
	var before := {}
	for key in board.order:
		before[key] = board.nodes[key]["pos"]
	var at: Vector2 = board.size / 2.0 + Vector2(300, 200)
	for e in [_button(at, true), _motion(at + Vector2(80, 40)), _motion(at + Vector2(200, 90)), _button(at + Vector2(200, 90), false)]:
		board._gui_input(e)
	for wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		var e := InputEventMouseButton.new()
		e.button_index = wheel
		e.pressed = true
		e.position = at
		board._gui_input(e)
	await process_frame
	for key in board.order:
		if board.nodes[key]["pos"] != before[key]:
			return _fail("%s moved under a drag or the wheel" % key)
	# Colours: an indicator is green for a good thing, red for a bad one, blue for the rest.
	for key in board.keys_of("indicator"):
		var want: String = {"high": "better", "low": "worse"}.get(str(board.nodes[key]["better"]), "steady")
		if str(board.nodes[key].get("state", "")) != want:
			return _fail("%s (better %s) is %s" % [key, board.nodes[key]["better"], board.nodes[key].get("state")])
	main.close_popup()
	for key in board.order:
		var kind: String = board.nodes[key]["kind"]
		main.open_node(key)
		await process_frame
		var want: String = {"policy": "policy", "indicator": "indicator", "group": "group", "introduce": "introduce", "centre": ""}[kind]
		if main.popup_kind() != want or (kind == "centre" and main.overlay_open() != "parliament"):
			return _fail("%s opened %s" % [key, main.popup_kind() if main.popup_kind() != "" else main.overlay_open()])
		main.close_popup()
		main.close_overlay()
	main.type_lever("basic_rate", 21.0)
	await _settle()
	if not main.policy_card().pending_text("basic_rate").contains("costs") or not main.game.pending().has("basic_rate"):
		return _fail("the change does not wait with its cost: " + main.policy_card().pending_text("basic_rate"))
	main.close_popup()
	await _settle()
	main.hover("policy:income_tax")
	if board.linked("policy:income_tax").is_empty() or board._links.is_empty():
		return _fail("pointing at Income tax shows no links")
	var centre: Dictionary = board.nodes["centre"]
	for key in board.keys_of("policy") + board.keys_of("indicator") + board.keys_of("group"):
		main.hover(key)
		for link in board._links:
			for p in link["points"]:
				if (p as Vector2).distance_to(centre["pos"]) < centre["r"]:
					return _fail("a link of %s passes under the centre" % key)
	main.hover("indicator:budget_balance")
	if board.linked("indicator:budget_balance").is_empty():
		return _fail("pointing at the budget balance shows nothing that moves it")
	main.hover("")
	main.open_overlay("budget")
	await _settle()
	var line: Dictionary = main.budget._lines[0]
	line["button"].pressed.emit()
	await process_frame
	if main.popup_kind() != "indicator" or main.indicator_card().name_shown != line["name"]:
		return _fail("the budget's first line did not open its popup")
	main.close_popup()
	main.close_overlay()
	# A model without [play.web]: an automatic board from the levers' groups and the headline.
	board.size = Vector2(1440, 900 - main.BAR_HEIGHT)  # a window's board (none without a display)
	main.start(main.find_file("models/mini/scenarios/island.toml"))
	await _settle()
	if board.authored or board.keys_of("policy").size() != 2 or board.keys_of("indicator").is_empty() or not board.overlaps().is_empty() 			or not board.keys_of("group").is_empty():
		return _fail("mini's automatic board: %d policies, %d indicators, %s" % [board.keys_of("policy").size(), board.keys_of("indicator").size(), board.overlaps()])
	print("board: ten areas, %d policies in force, %d to introduce on %d introduce nodes, %d indicators and 23 group arcs in six families, nothing overlapping at three sizes (labelled at rest: %s); unmoved by a drag or the wheel; indicator colours by `better`; every node opens its popup; a change waits with its cost; links shown, none under the centre; budget lines open; an automatic board for mini, its middle empty" % [policies, want_available, want_introduce, indicators, ", ".join(rested)])
	quit(0)


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	return e


func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = Vector2(40, 20)
	return e


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 4:
		await process_frame
