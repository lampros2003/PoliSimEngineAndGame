extends SceneTree
## Stage S13.2: the board, through the interface (models/uk/scenarios/2025.toml). The UK
## board is built from [play.web]: ten areas, 24 policies holding every lever the player
## has but Scotland's own income tax, 24 indicators; no two nodes, and no label shown at
## rest, nor four situation flags, overlap at 1366x768, 1920x1080 or 2560x1440; every node opens the right popup (the
## centre, Parliament); a basic rate typed in Income tax's popup waits with its cost in
## political capital; pointing at a policy shows its links; the Budget's lines open their
## popups. Then models/mini, which has no [play.web], gets an automatic board. Stage S13.4:
## the 18 interest groups round the centre in their five families, each family together;
## a label at rest for most nodes, none touching another node, label or flag at the three
## sizes; a group opens a group popup; models/mini's board has an empty middle.

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
	if policies != 24 or indicators != 24:
		return _fail("the board has %d policies and %d indicators" % [policies, indicators])
	var families := []
	for key in board.keys_of("group"):
		var family := str(board.nodes[key]["family"])
		if families.is_empty() or families[-1] != family:
			families.append(family)
	if board.keys_of("group").size() != 18 or families != ["Ages", "Incomes", "Work", "Families", "Places"]:
		return _fail("the groups: %d in families %s" % [board.keys_of("group").size(), families])
	var on_board: PackedStringArray = main.board_levers()
	for name in main.entries:
		var entry: Dictionary = main.entries[name]
		if entry["kind"] != "lever" or not entry.get("player", true):
			continue
		var scottish := str(entry.get("group", "")) == "Scottish income tax"
		if on_board.has(name) == scottish:
			return _fail("%s is %s the board" % [name, "on" if scottish else "missing from"])
	var own_size: Vector2 = board.size
	var rested := []
	for view in [Vector2(1366, 768), Vector2(1920, 1080), Vector2(2560, 1440)]:
		board.size = view - Vector2(0, main.BAR_HEIGHT)
		board.layout()
		# Four situations flagged at once must clear the nodes too.
		board.set_flags([{"key": "a", "text": "Recession", "tone": "bad"}, {"key": "b", "text": "High unemployment", "tone": "bad"},
			{"key": "c", "text": "Debt above a year's output", "tone": "bad"}, {"key": "d", "text": "Health service under strain", "tone": "bad"}])
		var found: PackedStringArray = board.overlaps()
		if not found.is_empty():
			return _fail("at %dx%d: %s" % [view.x, view.y, ", ".join(found)])
		var labelled := 0
		var labels := 0
		for key in board.order:
			if not board.nodes[key]["kind"] in ["centre", "flag"]:
				labels += 1
				labelled += 1 if board.nodes[key]["rest"] else 0
		if labelled < labels * 0.85:
			return _fail("at %dx%d only %d of %d nodes are labelled at rest" % [view.x, view.y, labelled, labels])
		rested.append("%d of %d at %dx%d" % [labelled, labels, view.x, view.y])
	board.size = own_size
	board.set_flags([])
	board.layout()
	for key in board.order:
		var kind: String = board.nodes[key]["kind"]
		if kind == "flag":
			continue
		main.open_node(key)
		await process_frame
		var want: String = {"policy": "policy", "indicator": "indicator", "group": "group", "centre": ""}[kind]
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
	print("board: ten areas, 24 policies, 24 indicators and 18 groups in five families, nothing overlapping at three sizes (labelled at rest: %s); every node opens its popup; a change waits with its cost; links shown; budget lines open; an automatic board for mini, its middle empty" % ", ".join(rested))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
