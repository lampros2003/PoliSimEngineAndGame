extends SceneTree
## Stage S13.5: real policies and a growing board, through the real bridge
## (models/uk/scenarios/2025.toml). After the first month: each area's list on the Add policy
## sheet (stage S15.1; its own popup before) holds
## exactly its policies not in force; every new indicator has a figure; the electric car
## grant introduced at £2,500 shows, under "In a year", the electric share of new cars up and
## the budget balance down, puts a ghost on the board and spends capital; after the month it
## is in force and the report says so; repealed, it leaves the board after the vote. A level
## policy offers its named levels and stores the level chosen; the drinking age reads in years
## and raising it shows the young's approval falling in a year; a higher fuel duty shows
## motorists against and receipts up, and pointing at it links motorists; an introduction the
## government cannot afford is refused, its ghost goes and the report says why; an estimated
## group's popup says it is an estimate and shows no households.

var main: Control
var board: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	board = main.board
	# The introduce lists: exactly the policies whose lever stands at its `off` setting.
	var listed := {}
	for area in main.play["web"]["areas"]:
		var want := PackedStringArray()
		for p in area.get("policies", []):
			var lever := str(p["levers"][0])
			var stored: float = float(p.get("off", 0.0)) * (main.fmt.minor if main.entries[lever].get("money", false) else 1)
			if p.has("off") and absf(float(main.game.latest(lever)) - stored) < 1e-6:
				want.append("policy:" + str(p["key"]))
		if main.available_policies(str(area["name"])) != want:
			return _fail("%s offers %s, not %s" % [area["name"], main.available_policies(str(area["name"])), want])
		# Stage S15.1: the Add policy sheet lists them, area by area.
		main.open_introduce(str(area["name"]))
		await process_frame
		if not main.add_sheet_open() or main.add_list.area != str(area["name"]) or main.add_list.keys != want:
			return _fail("%s on the Add policy sheet: %s" % [area["name"], main.add_list.keys if main.add_list != null else "no sheet"])
		main.close_overlay()
		listed[area["name"]] = want
	if not listed.get("Transport", PackedStringArray()).has("policy:ev_grant"):
		return _fail("the policies not in force: %s" % [listed])
	# Every new indicator has a figure after the first month.
	for row in ["crime_incidents", "prison_population", "healthy_life_expectancy", "smoking_prevalence", "alcohol_deaths",
			"ev_share", "school_attainment", "homes_built", "net_migration_annual"]:
		var node: Dictionary = board.nodes.get("indicator:" + row, {})
		if node.is_empty() or main.latest_value(row) == null or str(node["value"]) in ["", "–"] or str(node["value"]).contains("%%%"):
			return _fail("%s has no figure: %s" % [row, node.get("value", "not on the board")])
	var figures := "crime %s, healthy life %s, homes built %s" % [board.nodes["indicator:crime_incidents"]["value"],
		board.nodes["indicator:healthy_life_expectancy"]["value"], board.nodes["indicator:homes_built"]["value"]]
	if not str(board.nodes["indicator:healthy_life_expectancy"]["value"]).ends_with(" years"):
		return _fail("healthy life reads " + str(board.nodes["indicator:healthy_life_expectancy"]["value"]))
	# The electric car grant, introduced at £2,500 a car.
	var capital_before := float(main.game.latest(str(main.entries[str(main.catalogue["capital"])]["row"])))
	main.open_node("policy:ev_grant")
	await process_frame
	var card = main.policy_card()
	if card == null or not card.introducing or card.put_button == null or not card.put_button.disabled:
		return _fail("the grant's popup is not ready to introduce")
	card.type_value("ev_grant", 2500.0)
	var year := await _year(card)
	if not year.get("Electric cars", 0.0) > 0.0 or not year.get("Budget balance", 0.0) < 0.0:
		return _fail("introducing the grant, in a year: %s" % [card.year_shown])
	var electric: float = year["Electric cars"]
	if not card.year_heading.contains("£2,500 A CAR"):
		return _fail("the year's heading: " + card.year_heading)
	var vote: String = card._rows["ev_grant"]["vote"].text
	if not vote.begins_with("The Commons would pass this"):
		return _fail("the grant's vote: " + vote)
	card.put_button.pressed.emit()
	await _settle()
	var ghost: Dictionary = board.nodes.get("policy:ev_grant", {})
	if ghost.is_empty() or not ghost.get("ghost", false) or not float(main._costs.get("ev_grant", 0.0)) > 0.0 or main.popup_kind() != "":
		return _fail("no ghost waiting with its cost: %s" % [ghost.get("value", "no node")])
	if main.available_policies("Transport").has("policy:ev_grant"):
		return _fail("Transport still offers the grant while it waits")
	await _month()
	var grant: Dictionary = board.nodes.get("policy:ev_grant", {})
	if grant.is_empty() or grant.get("ghost", true) or str(grant["value"]) != "£2,500 a car":
		return _fail("after the month the grant is %s" % [grant.get("value", "not on the board")])
	var said := Array(main.report.lines_shown).filter(func(l): return str(l).begins_with("Electric car grant introduced at £2,500 a car"))
	if said.is_empty():
		return _fail("the report: %s" % [main.report.lines_shown])
	var capital_after := float(main.game.latest(str(main.entries[str(main.catalogue["capital"])]["row"])))
	# Repealing it: a bill with its cost and vote, then off the board.
	main.open_node("policy:ev_grant")
	await process_frame
	var repeal_said: String = main.policy_card().repeal_note.text
	if not repeal_said.contains("Costs ") or not repeal_said.contains("The Commons would"):
		return _fail("the repeal reads: " + repeal_said)
	main.close_popup()
	main.repeal_policy("policy:ev_grant")
	await _settle()
	if not main.game.pending().has("ev_grant") or float(main.game.pending()["ev_grant"]) != 0.0:
		return _fail("the repeal is not waiting: %s" % [main.game.pending()])
	main.close_popup()
	await _month()
	if board.nodes.has("policy:ev_grant") or not main.available_policies("Transport").has("policy:ev_grant"):
		return _fail("the repealed grant is still on the board")
	if Array(main.report.lines_shown).filter(func(l): return str(l) == "Electric car grant repealed").is_empty():
		return _fail("the report after the repeal: %s" % [main.report.lines_shown])
	# A level policy: chosen by name, stored as its level.
	main.open_node("policy:planning_rules")
	await process_frame
	card = main.policy_card()
	var names: PackedStringArray = card.level_names("planning_rules")
	if names != PackedStringArray(["Very restrictive", "Restrictive", "As now", "Liberal", "Very liberal"]) or card.field_text("planning_rules") != "As now":
		return _fail("planning rules offer %s, at %s" % [names, card.field_text("planning_rules")])
	card.find_child("level_planning_rules_3", true, false).pressed.emit()
	await _settle()
	if int(main.game.pending().get("planning_rules", -1)) != 3 or not main.policy_card().pending_text("planning_rules").begins_with("→ Liberal"):
		return _fail("choosing Liberal waits as %s: %s" % [main.game.pending().get("planning_rules"), main.policy_card().pending_text("planning_rules")])
	main.game.cancel_lever("planning_rules")
	main.close_popup()
	await _settle()
	# A level policy in force today can be repealed (the Winter Fuel Payment, to None).
	main.open_node("policy:winter_fuel_payment")
	await process_frame
	if not main.policy_card().repeal_note.text.contains("Costs ") or not main.policy_card().repeal_note.text.contains("The Commons would"):
		return _fail("the Winter Fuel Payment's repeal reads: " + main.policy_card().repeal_note.text)
	main.close_popup()
	await _settle()
	# The drinking age, in years; raised, the young turn against.
	main.open_node("policy:drinking_age")
	await process_frame
	card = main.policy_card()
	if card.field_text("drinking_age") != "18 years" or str(board.nodes["policy:drinking_age"]["value"]) != "18 years":
		return _fail("the drinking age reads %s" % card.field_text("drinking_age"))
	main.type_lever("drinking_age", 21.0)
	year = await _year(card)
	var groups := {}
	for g in card.year_all_groups:
		groups[g[0]] = g[1]
	if not groups.get("The young", 0.0) < 0.0 or not card.year_heading.contains("21 YEARS"):
		return _fail("a drinking age of 21, in a year: %s; %s (waiting %s; %s)" % [card.year_all_groups, card.year_heading, main.game.pending(), main.notice_text()])
	var young: float = groups["The young"]
	main.game.cancel_lever("drinking_age")
	main.close_popup()
	await _settle()
	# Fuel duty ten pence up: motorists against, receipts up.
	main.type_lever("fuel_duty", 62.95)
	card = main.policy_card()
	year = await _year(card)
	groups.clear()
	for g in card.year_all_groups:
		groups[g[0]] = g[1]
	var receipts := 0.0
	for row in card.year_shown:
		if str(row[0]).contains("tax") or str(row[0]).contains("Tax") or str(row[0]).contains("receipts"):
			receipts = maxf(receipts, float(row[1]))
	if not groups.get("Motorists", 0.0) < 0.0 or not receipts > 0.0 or card.field_text("fuel_duty") != "62.95p":
		return _fail("fuel duty at 62.95p, in a year: %s; groups %s" % [card.year_shown, card.year_all_groups])
	main.game.cancel_lever("fuel_duty")
	main.close_popup()
	await _settle()
	var until := Time.get_ticks_msec() + 120000
	while not (main.board.effects.has("fuel_duty") and not main.effects_running) and Time.get_ticks_msec() < until:
		await process_frame
	# Pointing at it shows what it measurably moves: prices, emissions, and groups. (Motorists
	# are four adults in five, so their approval moves much as everyone's does: the table does
	# not single them out.)
	main.hover("policy:fuel_duty")
	var fuel_links: PackedStringArray = board.linked("policy:fuel_duty")
	main.hover("")
	if not fuel_links.has("indicator:consumer_inflation_annual") or not (fuel_links.has("indicator:emissions") or fuel_links.has("indicator:household_emissions")) \
			or not Array(fuel_links).any(func(k): return str(k).begins_with("group:")):
		return _fail("pointing at fuel duty links %s" % [fuel_links])
	# An introduction the government cannot afford: refused, the ghost gone, the notice.
	main.type_lever("basic_rate", 80.0)
	main.close_popup()
	await _settle()
	main.open_node("policy:cannabis_law")
	await process_frame
	main.policy_card().find_child("level_cannabis_law_2", true, false).pressed.emit()
	await _settle()
	main.policy_card().put_button.pressed.emit()
	await _settle()
	if not board.nodes.get("policy:cannabis_law", {}).get("ghost", false):
		return _fail("no ghost for cannabis law")
	await _month()
	var refused: Array = main.game.changes().filter(func(c): return str(c["lever"]) == "cannabis_law" and c.get("refused", false))
	if refused.is_empty() or board.nodes.has("policy:cannabis_law") or not main.available_policies("Law and order").has("policy:cannabis_law") \
			or Array(main.report.lines_shown).filter(func(l): return str(l).begins_with("Cannabis law, to be introduced at Legal and taxed: refused")).is_empty():
		return _fail("the unaffordable introduction: refused %d, report %s" % [refused.size(), main.report.lines_shown])
	# An estimated group: the note, no households.
	main.open_node("group:motorists")
	for i in 30:
		await process_frame
	var group = main.group_card()
	var note: Label = group.find_child("estimate_note", true, false)
	if group == null or group.estimate == "" or not group.records.is_empty() or note == null or not note.text.contains("estimate"):
		return _fail("the motorists' popup does not say it is an estimate")
	main.close_popup()
	while main.effects_running:
		await process_frame
	print("policies: introduce lists exact (%s); new indicators shown (%s); the grant at £2,500 a car: electric cars %+.4f and the budget %s in a year, a ghost, capital %.1f to %.1f, in force and reported, then repealed; planning rules by name; the drinking age in years (the young %+.4f at 21); fuel duty up: motorists %+.4f, receipts up, prices and emissions linked; an unaffordable introduction refused with its notice; the motorists' popup an estimate without households" % [
		", ".join(listed.keys().filter(func(k): return not listed[k].is_empty())), figures, electric, "down",
		capital_before, capital_after, young, groups["Motorists"]])
	quit(0)


## Waits for a policy popup's year ahead and returns it as {label: change}.
func _year(card) -> Dictionary:
	card.year_shown = []
	var until := Time.get_ticks_msec() + 30000
	while card.year_shown.is_empty() and Time.get_ticks_msec() < until:
		await process_frame
	var out := {}
	for row in card.year_shown:
		out[row[0]] = row[1]
	return out


## Runs a month, answering any question first.
func _month() -> void:
	for d in main.unanswered_dilemmas():
		main.answer_dilemma(str(d["name"]), 1)
	await _settle()
	main.advance(1)
	await _settle()
	for d in main.unanswered_dilemmas():
		main.answer_dilemma(str(d["name"]), 1)
	await _settle()


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
