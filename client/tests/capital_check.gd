extends SceneTree
## Stage S12.5: political capital through the interface (models/uk/scenarios/2025.toml).
## After a month the capital shows at the right of the page strip; typing a basic rate of
## 22% shows what the bill costs (5 + 60 x 0.02 = 6.2); two big bills in one month (41
## each, with about 45 to spend) leave the second refused, and the player is told.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	if main.failed:
		return _fail("the game did not start")
	if not main._capital.visible or not main._capital.text.begins_with("Political capital "):
		return _fail("the capital reads: " + main._capital.text)
	main.levers.type_value("basic_rate", 22.0)
	await _settle()
	var pending: String = main.levers._rows["basic_rate"]["pending"].text
	if not pending.ends_with("costs 6.2 political capital") or not main._capital.text.ends_with("6.2 for bills waiting"):
		return _fail("the cost reads: %s / %s" % [pending, main._capital.text])
	main.levers.type_value("basic_rate", 80.0)
	main.levers.type_value("vat_rate", 50.0)
	await _settle()
	if not main.levers.capital_note.text.contains("Not all of them can be put to the Commons"):
		return _fail("no warning before the month: " + main.levers.capital_note.text)
	main.advance(1)
	await _settle()
	if not main._message.visible or not main._message_text.text.contains("Not enough political capital: a bill was not put to the Commons"):
		return _fail("the refusal was not announced: " + main._message_text.text)
	if main.game.latest("vat_rate") != 0.2 or main.game.latest("basic_rate") != 0.8:
		return _fail("the rates are %s and %s" % [main.game.latest("basic_rate"), main.game.latest("vat_rate")])
	print("capital: shown, a bill's cost shown before it is made, and a bill the government cannot pay for refused and announced")
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
