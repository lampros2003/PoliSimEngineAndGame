extends SceneTree
## Stage S7.1: the start screen, through the interface. Opens the client without
## --scenario, checks that it lists the United Kingdom and Valmora and offers the example
## mod (mods/dog_licence) for the UK only, ticks it, starts a new game, and checks that the
## mod's lever is on the board, its receipts in the budget once set, and its name in the
## title. Stage S17.1: the mod adds something the model lacks (a dog licence), and the
## wealth tax that was the example, which doubles the UK's own since stage S15, is not
## offered.

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
	if screen.tick("wealth_tax"):
		return _fail("the start screen offers a wealth tax as a mod, which the UK model already has")
	if not screen.tick("dog_licence"):
		return _fail("the dog licence mod is not offered for the UK")
	screen._choice.select(1)
	screen._choice.item_selected.emit(1)
	if screen.tick("dog_licence"):
		return _fail("the UK's mod is offered for Valmora")
	screen._choice.select(0)
	screen._choice.item_selected.emit(0)
	screen.tick("dog_licence")
	screen._new.pressed.emit()
	await _settle()
	if not main.started or main.start_screen != null:
		return _fail("the game did not start: %s" % main.notice_text())
	# What the mod adds is not in the model without it.
	if not main.board_levers().has("dog_licence_fee"):
		return _fail("the mod's lever is not on the board")
	if not main.title_text().contains("WITH A DOG LICENCE"):
		return _fail("the title does not name the mod: %s" % main.title_text())
	var refused: String = main.game.set_lever("dog_licence_fee", 50.0)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	var paid := float(main.game.latest("dog_licence_paid"))
	if paid <= 0.0:
		return _fail("no dog licence was paid for")
	var lines := PackedStringArray()
	for line in main.budget._lines:
		lines.append(str(line["entry"].get("label", line["name"])))
	if not lines.has("Dog licences"):
		return _fail("the budget has no dog licences line: %s" % [lines])
	print("start screen: the UK and Valmora listed, the dog licence mod offered for the UK (and no wealth tax, which the model has), chosen, and in play (£%.0fm a year)" % (paid * 12.0 / 100.0 / 1e6))
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
