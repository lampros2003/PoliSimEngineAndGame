extends SceneTree
## Hot reload through the interface, on a copy of a model (--model-dir=DIR, with
## --scenario pointing into it). A typo must be reported and the game must carry on with
## the old model; a real change must take effect the next month; and after a run-time
## error, reloading the corrected model must let the game carry on.

var main: Control


func _initialize() -> void:
	var model_dir := ""
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-dir="):
			model_dir = arg.substr(12)
		if arg.begins_with("--shots="):
			shots = arg.substr(8)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(3)
	await _settle()
	var economy := model_dir.path_join("economy.toml")
	var original := FileAccess.get_file_as_string(economy)
	# 1. A typo in a formula.
	_write(economy, original.replace('expr = "consumption_total - vat + gov_spending"', 'expr = "consumption_totl - vat + gov_spending"'))
	main._reload.pressed.emit()
	await _settle()
	var message: String = main._message_text.get_parsed_text()
	if not main._message.visible or not message.contains("consumption_totl"):
		_fail("the typo was not reported: " + message)
		return
	if shots != "":
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(shots.path_join("06-reload-error.png"))
	main.advance(1)
	await _settle()
	if main.game.steps_done() != 4 or main.failed:
		_fail("the game did not carry on after the typo")
		return
	var spending_before := int(main.game.latest("consumption_total"))
	# 2. A real change: households spend 90% of income instead of 80%.
	_write(economy, original.replace("central = 0.80", "central = 0.90"))
	main._reload.pressed.emit()
	await _settle()
	if not main._message_text.get_parsed_text().begins_with("Model reloaded"):
		_fail("the corrected model was not reloaded: " + main._message_text.get_parsed_text())
		return
	main.advance(1)
	await _settle()
	var spending_after := int(main.game.latest("consumption_total"))
	if spending_after <= spending_before * 1.05:
		_fail("spending did not jump after the change: %d then %d" % [spending_before, spending_after])
		return
	# 3. A run-time failure, then the correction: the game must carry on from the last
	# good month once the corrected model is reloaded.
	var phase := "government"
	_write(economy, original + '\n[var.trap]\ntype = "int"\nunit = "1"\nphase = "%s"\nrange = [0, 0]\nexpr = "1"\n' % phase)
	main._reload.pressed.emit()
	await _settle()
	var good: int = main.game.steps_done()
	main.advance(1)
	await _settle()
	if not main.failed or main.game.steps_done() != good:
		_fail("the run-time error did not stop the game")
		return
	_write(economy, original)
	main._reload.pressed.emit()
	await _settle()
	main.advance(1)
	await _settle()
	if main.failed or main.game.steps_done() != good + 1:
		_fail("the game did not carry on after the corrected model was reloaded (%d months, failed %s)" % [main.game.steps_done(), main.failed])
		return
	print("reload run: typo reported, game carried on, change took effect (spending %d -> %d), recovered from a run-time error" % [spending_before, spending_after])
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _settle() -> void:
	for i in 3:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 3:
		await process_frame


func _fail(message: String) -> void:
	printerr("reload run failed: " + message)
	quit(1)
