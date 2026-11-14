extends SceneTree
## Opens a model the client was not written for (models/mini: other sector, lever and
## flow names) and checks the screen is built from its catalogue: two budget lines, two
## levers, two headline figures, and a lever change that reaches the budget.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	var problems := PackedStringArray()
	if main.failed or main.game.catalogue().is_empty():
		problems.append("the model did not open")
	if main.budget._lines.size() != 2:
		problems.append("expected 2 budget lines, found %d" % main.budget._lines.size())
	if main.levers._rows.size() != 2:
		problems.append("expected 2 levers, found %d" % main.levers._rows.size())
	if main._cards.size() != 2:
		problems.append("expected 2 headline figures, found %d" % main._cards.size())
	main.advance(1)
	await _settle()
	var before := int(main.game.latest("pensions.total"))
	main.levers.type_value("pension", 1000.0)
	# The change goes to the simulation thread first; the month buttons wait for it.
	await _settle()
	main.advance(1)
	await _settle()
	var after := int(main.game.latest("pensions.total"))
	# 250 retired people times 100 euros more, in cents.
	if after - before != 250 * 100 * 100:
		problems.append("the pension change moved pensions by %d cents, not 2,500,000" % (after - before))
	if main.budget._lines[1]["cells"][0].text != "€250,000":
		problems.append("the budget shows %s for pensions" % main.budget._lines[1]["cells"][0].text)
	if problems.is_empty():
		print("second model: screen built from its catalogue; a lever change reached the budget")
		quit(0)
	else:
		printerr("second model: " + "; ".join(problems))
		quit(1)


func _settle() -> void:
	for i in 3:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 3:
		await process_frame
