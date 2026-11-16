extends SceneTree
## Stage S7.4: a game in another language. From the start screen, picks Valmora, which
## has a French text (models/valmora/text/fr.toml), and French; checks that the budget and
## the policy panel use the French words, that the UK offers no French, and that a saved
## game loads in French too. --save=PATH is where the test saves.

var main: Control


func _initialize() -> void:
	var save := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			save = arg.substr(7)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	var screen = main.start_screen
	if screen == null:
		return _fail("the start screen is not shown")
	if screen.choose_language("fr"):
		return _fail("French is offered for the UK, which has no French text")
	screen._choice.select(1)
	screen._choice.item_selected.emit(1)
	if not screen._language.visible or not screen.choose_language("fr"):
		return _fail("French is not offered for Valmora")
	screen._new.pressed.emit()
	await _settle()
	if not main.started:
		return _fail("the game did not start: %s" % main.notice_text())
	main.save_path = save
	main.advance(1)
	await _settle()
	if not _budget_says("Impôt sur le revenu"):
		return _fail("the budget is not in French")
	if not main.board_levers().has("basic_rate") or str(main.entries["basic_rate"]["label"]) != "Taux de base de l'impôt sur le revenu":
		return _fail("the policy panel is not in French: %s" % main.entries.get("basic_rate", {}).get("label", ""))
	main.save_game()
	await _settle()
	main.load_game()
	await _settle()
	if not _budget_says("Impôt sur le revenu"):
		return _fail("the loaded game is not in French")
	print("language: Valmora in French from the start screen, budget and policy panel, and after a load")
	quit(0)


func _budget_says(label: String) -> bool:
	for line in main.budget._lines:
		if str(line["entry"].get("label", "")) == label:
			return true
	return false


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
