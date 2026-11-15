extends SceneTree
## Stage S7.0: a saved game that outlives its model files. tools/check_client.py runs this
## twice on a copy of Valmora. With --phase=save it plays three months, raises the basic
## rate to 30% for the fourth, and saves to --save=PATH. The check then changes the model
## files (a new state, and the basic rate limited to 25%) and runs it with --phase=load,
## which loads the save and checks that the game carries on with the new model, the rate
## moved to its new limit, and the player told what changed.

var main: Control


func _initialize() -> void:
	var phase := ""
	var save := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.substr(8)
		elif arg.begins_with("--save="):
			save = arg.substr(7)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed:
		return _fail("the game did not start")
	main.save_path = save
	if phase == "save":
		main.advance(3)
		await _settle()
		var refused: String = main.game.set_lever("basic_rate", 0.3)
		if refused != "":
			return _fail(refused)
		await _settle()
		main.advance(1)
		await _settle()
		main.save_game()
		await _settle()
		if not FileAccess.file_exists(save):
			return _fail("the game was not saved")
		print("saved after %d months" % main.game.steps_done())
		quit(0)
		return
	main.load_game()
	await _settle()
	if main.game.steps_done() != 4:
		return _fail("the saved game did not load: %d months, message %s" % [main.game.steps_done(), main.notice_text()])
	var said: String = main.notice_text()
	for words in ["earlier version of the model", "Months run", "Basic income tax rate"]:
		if not said.contains(words):
			return _fail("the player was not told %s: %s" % [words, said])
	if absf(float(main.game.latest("basic_rate")) - 0.25) > 1e-12:
		return _fail("the basic rate was not moved to its new limit: %s" % main.game.latest("basic_rate"))
	main.advance(1)
	await _settle()
	if main.failed or main.game.steps_done() != 5 or int(main.game.latest("months_run")) != 1:
		return _fail("the game did not carry on with the new model")
	print("migration: a save from older model files loaded, the rate moved to its new limit, the player told, play went on")
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
