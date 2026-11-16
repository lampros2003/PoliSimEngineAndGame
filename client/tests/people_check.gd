extends SceneTree
## Stage S13.4: the people, through the real bridge (models/uk/scenarios/2025.toml). After
## three months: a group's popup shows the approval the model has for it, and the drivers
## shown are the model's; Northern Ireland shows a dash, not a percentage; eight households
## are shown for a group, each in it (its flag asked for as a column); a household's account
## adds up to its net income; a basic rate of 21% shows, in "In a year", high incomes'
## approval falling by more than low incomes'; pointing at Income tax shows the budget
## balance and unemployment going up (stage S14.1: green and red, as every link is by whether
## it is good for what it reaches). Then models/valmora, which has no groups, gets a board
## with an empty middle.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(3)
	await _settle()
	if main.failed or main.game.steps_done() != 3:
		return _fail("the game did not play three months")
	var board = main.board
	# The young: approval and drivers as the model has them.
	main.open_node("group:young")
	await process_frame
	var card = main.group_card()
	if main.popup_kind() != "group" or card == null:
		return _fail("the young's node opened %s" % main.popup_kind())
	var approval: float = main.game.latest("approval_young")
	var cells: Dictionary = main.game.cells("group_approval")
	if card.index < 0 or not is_equal_approx(cells["values"][card.index], approval) or str(cells["labels"][card.index]) != "The young":
		return _fail("the young are member %d of the groups: %s" % [card.index, cells])
	if card.approval_text != main.fmt.value(main.rows["approval_young"], approval, true, false) or not card.approval_text.ends_with("%"):
		return _fail("the young's popup shows %s, the model %s" % [card.approval_text, approval])
	var drivers: Array = main._group_drivers()
	if card.drivers_shown.size() != 6 or drivers.size() != 6:  # stage S13.8: the public finances is the sixth
		return _fail("drivers shown: %s" % [card.drivers_shown])
	var moving := false
	for i in 5:
		var model: float = main.game.cells(drivers[i][1])["values"][card.index]
		if card.drivers_shown[i][0] != drivers[i][0] or not is_equal_approx(card.drivers_shown[i][1], model):
			return _fail("driver %s shows %s, the model %s" % [drivers[i][0], card.drivers_shown[i][1], model])
		moving = moving or model != 0.0
	if not moving:
		return _fail("no driver moved the young in three months")
	# Eight households of the group, each in it.
	for i in 1200:
		if not card.records.is_empty():
			break
		await process_frame
	if card.records.size() != 8:
		return _fail("%d households shown for the young" % card.records.size())
	for record in card.records:
		if record.get("household_in_young") != true:
			return _fail("household %s is not among the young: %s" % [record.get("id"), record])
	# A household's account adds up as shown.
	var young_text: String = card.approval_text
	card.household_opened.emit(card.records[0])
	await process_frame
	if main.popup_kind() != "household":
		return _fail("a household opened %s" % main.popup_kind())
	var account = main.popup.content
	var total := 0.0
	for line in account.lines:
		total += float(line[1])
	if account.lines.size() != 5 or absf(total - account.net) > float(main.fmt.minor):
		return _fail("the account %s adds to %s, its net income %s" % [account.lines, total, account.net])
	var net_text: String = main.fmt.money(account.net)
	main.close_popup()
	# Northern Ireland: no governing candidate, so a dash.
	main.open_node("group:northern_ireland")
	await process_frame
	var ni = main.group_card()
	if ni.approval_text != "–" or str(board.nodes["group:northern_ireland"]["value"]) != "–":
		return _fail("Northern Ireland shows %s (board %s)" % [ni.approval_text, board.nodes["group:northern_ireland"]["value"]])
	main.close_popup()
	# Raising the basic rate: high incomes turn against it more than low incomes.
	main.type_lever("basic_rate", 21.0)
	await _settle()
	var policy = main.policy_card()
	for i in 600:
		if not policy.year_shown.is_empty():
			break
		await process_frame
	var groups := {}
	for g in policy.year_all_groups:
		groups[g[0]] = g[1]
	var shown: Array = policy.year_groups.map(func(g): return g[0])
	if not shown.has("High incomes") or not groups.get("High incomes", 0.0) < 0.0 or not groups["High incomes"] < groups.get("Low incomes", 0.0):
		return _fail("in a year, the groups: %s (shown %s)" % [groups, shown])
	main.game.cancel_lever("basic_rate")
	main.close_popup()
	await _settle()
	# Income tax's links: the budget balance up, unemployment up.
	for i in 3000:
		if main.board.effects.has("basic_rate") and not main.effects_running:
			break
		await process_frame
	main.hover("policy:income_tax")
	var signs := {}
	for link in board._links:
		signs[link["to"]] = link["sign"]
	if signs.get("indicator:budget_balance", 0.0) != 1.0 or signs.get("indicator:unemployment_rate", 0.0) != 1.0:
		return _fail("pointing at Income tax: %s" % [signs])
	var group_links: Array = signs.keys().filter(func(k): return str(k).begins_with("group:"))
	if group_links.is_empty():
		return _fail("pointing at Income tax shows no group")
	# Stage S14.1: a link's colour says whether it is good for what it reaches: the balance
	# up is good, unemployment up bad, a group's approval down bad.
	for link in board._links:
		var better := str(board.nodes[link["to"]]["better"])
		var want := "steady" if better == "" else ("better" if (float(link["sign"]) > 0.0) == (better == "high") else "worse")
		if str(link["tone"]) != want:
			return _fail("the link to %s (sign %s, better %s) is %s" % [link["to"], link["sign"], better, link["tone"]])
	if board._links.filter(func(l): return l["to"] == "indicator:budget_balance")[0]["tone"] != "better" 			or board._links.filter(func(l): return l["to"] == "indicator:unemployment_rate")[0]["tone"] != "worse":
		return _fail("Income tax's links to the balance and unemployment are not green and red")
	main.hover("")
	# A model without groups: an empty middle, nothing overlapping.
	board.size = Vector2(1440, 900 - main.BAR_HEIGHT)
	main.start(main.find_file("models/valmora/scenarios/term.toml"))
	await _settle()
	if not board.keys_of("group").is_empty() or not board.overlaps().is_empty() or main.failed:
		return _fail("valmora's board: %d groups, %s" % [board.keys_of("group").size(), board.overlaps()])
	print("people: the young back the government at %s, as the model has it, its six drivers the model's; Northern Ireland shows a dash; eight of the young's households, all young, one's account adding up (%s); a 21%% basic rate costs high incomes %.2f pts and low incomes %.2f; Income tax links the budget balance and unemployment up, and %d groups; valmora's board has no groups" % [
		young_text, net_text, groups["High incomes"] * 100.0, groups.get("Low incomes", 0.0) * 100.0, group_links.size()])
	quit(0)


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
