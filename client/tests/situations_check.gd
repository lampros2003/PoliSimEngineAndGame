extends SceneTree
## Stage S7.3: a situation brought on through the interface. In the UK's 2025 scenario,
## after a quiet month (no situation shown), cuts health spending by about a third and plays
## a month: a recession begins, the player is told, and the strip under the headline shows it
## with the month it began.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or main.situations.size() < 5:
		return _fail("the UK's situations are not in the catalogue: %d" % main.situations.size())
	main.advance(1)
	await _settle()
	if main._situation_strip.visible:
		return _fail("a situation is shown in a quiet first month")
	var refused: String = main.game.set_lever("spending_health", 14e9)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	if main.game.latest("recession") != true:
		return _fail("no recession after health spending was cut")
	if not main._message.visible or not main._message_text.text.contains("Recession"):
		return _fail("the player was not told: %s" % main._message_text.text)
	var chip: Node = main._situation_strip.get_node_or_null("situation_recession")
	if chip == null or not main._situation_strip.visible:
		return _fail("the recession is not on the strip")
	var text: String = (chip.get_child(0) as Label).text
	if text != "Recession · since February 2025":
		return _fail("the strip shows %s" % text)
	print("situations: a third off health spending brings a recession, announced and shown: %s" % text)
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
