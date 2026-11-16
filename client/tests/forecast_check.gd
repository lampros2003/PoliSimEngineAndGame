extends SceneTree
## Stage S13.3: looking ahead through the real bridge (models/uk/scenarios/2025.toml).
## After a month: a basic rate of 21% typed in Income tax's popup shows, under "In a year",
## income tax receipts up and household income down; the Commons vote line says the bill
## would pass; once the effects table has arrived, Income tax's links on the board are
## measured and point the way the table has the basic rate move them; and a VAT rise typed after an expensive
## income tax bill says there is not enough political capital for it.

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
	if not year.get("Income tax", 0.0) > 0.0 or not year.get("Household income", 0.0) < 0.0:
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
	main.type_lever("basic_rate", 80.0)
	main.type_lever("vat_rate", 50.0)
	await _settle()
	var refused: String = main.policy_card()._rows["vat_rate"]["vote"].text
	while main.effects_running:  # quit only once the table's thread is done
		await process_frame
	if not refused.contains("Not enough political capital: needs "):
		return _fail("the unaffordable bill reads: " + refused)
	print("forecast: a basic rate rise shows income tax up (%s) and household income down (%s) in a year; %s; %d measured links; \"%s\"" % [
		year["Income tax"], year["Household income"], vote, links.size(), refused])
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
