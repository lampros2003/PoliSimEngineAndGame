extends SceneTree
## Stage S13.3: looking ahead through the real bridge (models/uk/scenarios/2025.toml).
## After a month: a basic rate of 21% typed in Income tax's popup shows, under "In a year",
## income tax receipts up and the budget balance up (stage S14.5; household income down
## before); the Commons vote line says the bill
## would pass; once the effects table has arrived, Income tax's links on the board are
## measured and point the way the table has the basic rate move them; and a VAT rise typed after an expensive
## income tax bill says there is not enough political capital for it. A value typed while
## the engine is still on an earlier request (an effects table just asked for) stays among
## the changes waiting in every frame, and its year ahead still arrives.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	if not main.game.has_method("request_forecast") or not main.game.has_method("request_effects"):
		return _fail("the bridge has no look-ahead calls")
	main.type_lever("basic_rate", 21.0)
	await _settle()
	var card = main.policy_card()
	for i in 600:
		if not card.year_shown.is_empty():
			break
		await process_frame
	var year := {}
	for row in card.year_shown:
		year[row[0]] = row[1]
	# Stage S14.5: the budget balance up, where household income down was checked before: with
	# Bank Rate and debt interest on the model, household income's move no longer ranks among
	# the rows shown.
	if not year.get("Income tax", 0.0) > 0.0 or not year.get("Budget balance", 0.0) > 0.0:
		return _fail("in a year: %s" % [card.year_shown])
	var vote: String = card._rows["basic_rate"]["vote"].text
	if not vote.begins_with("The Commons would pass this "):
		return _fail("the vote reads: " + vote)
	# The effects table, asked for after the month, arrives off the worker.
	for i in 3000:
		if main.board.effects.has("basic_rate"):
			break
		await process_frame
	main.close_popup()
	await _settle()
	main.hover("policy:income_tax")
	var links: Array = main.board._links
	if links.is_empty() or links.any(func(l): return not l["measured"]):
		return _fail("Income tax's links are not measured: %s" % [links])
	for link in links:
		var row := str(main.board.nodes[link["to"]]["row"])
		var best := float(main.board.effects["basic_rate"].get(row, 0.0))  # Income tax's first lever
		if signf(best) != float(link["sign"]):
			return _fail("the link to %s points %s, the table %s" % [row, link["sign"], best])
	main.hover("")
	# A value typed while the engine is on an earlier request: the update that request sends
	# back was made before the change, and must not take it out of what the interface holds
	# (it did, for a moment; on a slow machine long enough that no forecast was asked for).
	main.game.cancel_lever("basic_rate")
	await _settle()
	while main.effects_running:
		await process_frame
	main.open_node("policy:drinking_age")
	await process_frame
	card = main.policy_card()
	main._measured.clear()
	main._ask_effects(PackedStringArray())
	main.type_lever("drinking_age", 21.0)
	card.year_shown = []
	var until := Time.get_ticks_msec() + 30000
	while card.year_shown.is_empty() and Time.get_ticks_msec() < until:
		if not main.game.pending().has("drinking_age"):
			return _fail("the drinking age typed was lost from the changes waiting: %s" % [main.game.pending()])
		await process_frame
	if card.year_shown.is_empty() or not card.year_heading.contains("21 YEARS"):
		return _fail("a value typed during an effects request, in a year: %s; %s" % [card.year_shown, card.year_heading])
	main.game.cancel_lever("drinking_age")
	main.close_popup()
	await _settle()
	main.type_lever("basic_rate", 80.0)
	main.type_lever("vat_rate", 50.0)
	await _settle()
	var refused: String = main.policy_card()._rows["vat_rate"]["vote"].text
	while main.effects_running:  # quit only once the table's thread is done
		await process_frame
	if not refused.contains("Not enough political capital: needs "):
		return _fail("the unaffordable bill reads: " + refused)
	print("forecast: a basic rate rise shows income tax up (%s) and the budget balance up (%s) in a year; %s; %d measured links; a value typed during an effects request kept and forecast; \"%s\"" % [
		year["Income tax"], year["Budget balance"], vote, links.size(), refused])
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
