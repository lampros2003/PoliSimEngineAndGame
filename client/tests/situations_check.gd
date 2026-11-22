extends SceneTree
## Stage S7.3: a situation brought on through the interface. In the UK's 2025 scenario,
## after a quiet month (no situation shown), cuts health spending by about a third and plays
## a month: a recession begins, the player is told (stage S14.1: once, in the month's report,
## which opens for it), and a flag on the strip shows it with the month it began.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or main.situations.size() < 5:
		return _fail("the UK's situations are not in the catalogue: %d" % main.situations.size())
	main.advance(1)
	await _settle()
	if not main.strip.flags.is_empty():
		return _fail("a situation is shown in a quiet first month")
	var refused: String = main.game.set_lever("spending_health", 14e9)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	if main.game.latest("recession") != true:
		return _fail("no recession after health spending was cut")
	if not main.report.visible or not Array(main.report.lines_shown).has("Recession began") or main.notice_text().contains("Recession"):
		return _fail("the player was not told once: report %s %s, notice %s" % [main.report.visible, main.report.lines_shown, main.notice_text()])
	var text: String = main.flag_text("situation_recession")
	if text != "Recession · since February 2025":
		return _fail("the flag shows %s" % text)
	print("situations: a third off health spending brings a recession, announced and shown: %s" % text)
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
