extends SceneTree
## Stage S7.1: the start screen, through the interface. Opens the client without
## --scenario, checks that it lists the United Kingdom and Valmora and offers the example
## mod (mods/wealth_tax) for the UK only, ticks it, starts a new game, and checks that the
## mod's lever is on the board, its tax in the budget once set, and its name in the
## title.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	var screen = main.start_screen
	if screen == null or not screen.visible or main.started:
		return _fail("the start screen is not shown")
	var titles := PackedStringArray()
	for scenario in screen.scenarios:
		titles.append(str(scenario["title"]))
	if titles != PackedStringArray(["The United Kingdom, 2025", "Valmora (a test country)"]):
		return _fail("the start screen lists %s" % [titles])
	if not screen.tick("wealth_tax"):
		return _fail("the wealth tax mod is not offered for the UK")
	screen._choice.select(1)
	screen._choice.item_selected.emit(1)
	if screen.tick("wealth_tax"):
		return _fail("the UK's mod is offered for Valmora")
	screen._choice.select(0)
	screen._choice.item_selected.emit(0)
	screen.tick("wealth_tax")
	screen._new.pressed.emit()
	await _settle()
	if not main.started or main.start_screen != null:
		return _fail("the game did not start: %s" % main.notice_text())
	if not main.board_levers().has("wealth_tax_rate"):
		return _fail("the mod's lever is not on the board")
	if not main.title_text().contains("WITH A WEALTH TAX"):
		return _fail("the title does not name the mod: %s" % main.title_text())
	var refused: String = main.game.set_lever("wealth_tax_rate", 0.01)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	var paid := float(main.game.latest("wealth_tax_paid"))
	if paid <= 0.0:
		return _fail("no wealth tax was paid")
	var lines := PackedStringArray()
	for line in main.budget._lines:
		lines.append(str(line["entry"].get("label", line["name"])))
	if not lines.has("Wealth tax"):
		return _fail("the budget has no wealth tax line: %s" % [lines])
	print("start screen: the UK and Valmora listed, the wealth tax mod offered for the UK, chosen, and in play (£%.1fbn a year)" % (paid * 12.0 / 100.0 / 1e9))
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
