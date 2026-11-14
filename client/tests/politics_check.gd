extends SceneTree
## Stage S5.5: the politics panel and election night, through the interface.
##   --expect=office  (models/uk/scenarios/2025.toml) after a month the panel shows the 2024
##                    House and the next election in July 2029;
##   --expect=lost    (models/uk/scenarios/early_election.toml) the election in the second
##                    month is announced, the player has lost office, and time stops.

var main: Control


func _initialize() -> void:
	var expect := "office"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect="):
			expect = arg.substr(9)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or not main.politics.visible:
		return _fail("no politics panel")
	main.advance(1 if expect == "office" else 2)
	await _settle()
	var panel = main.politics
	if expect == "office":
		var seats := PackedStringArray()
		for row in panel._rows:
			seats.append(row["cells"][3].text)
		if seats != PackedStringArray(["411", "121", "72", "5", "4", "9", "4", "18", "6"]):
			return _fail("the House is not 2024's: %s" % [seats])
		if panel._election.text != "Next general election: July 2029, in 54 months":
			return _fail("the next election reads: " + panel._election.text)
		if not panel._summary.text.begins_with("Government: Centre-left, 411 of 650 seats"):
			return _fail("the summary reads: " + panel._summary.text)
		if main.lost or main._advance[0].disabled:
			return _fail("the game stopped")
		print("politics: the 2024 House, the government's poll rating and the July 2029 election shown")
	else:
		if main._dialog == null or not main._dialog.visible or not main._dialog.title.contains("lost office"):
			return _fail("election night was not announced")
		if not main.lost or not main._advance[0].disabled:
			return _fail("the game did not stop when the player lost office")
		var steps: int = main.game.steps_done()
		main.advance(1)
		await _settle()
		if main.game.steps_done() != steps:
			return _fail("time moved on after the game ended")
		print("politics: election night announced, the player out of office, the game over")
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
