extends SceneTree
## Plays 60 months of the toy scenario through the real interface: lever changes are
## typed into the policy inputs and time is advanced by pressing the buttons. Along the
## way it saves, reloads the (unchanged) model, and at the end loads the save. Writes
## "step,hash" lines to --out=PATH for tools/check_client.py to compare with the runner.

const CHANGES := {
	6: [["basic_rate", 25.0]],
	15: [["gov_purchases", 1550000000.0]],
	30: [["benefit_rate", 900.0], ["vat_rate", 17.5]],
	42: [["personal_allowance", 1100.5]],
}

var main: Control


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.game.steps_done() != 0 or main.failed:
		_fail("the game did not start")
		return
	var next_month: Button = main.find_child("advance_1", true, false)
	var saved_hash := ""
	for month in range(60):
		if CHANGES.has(month):
			for change in CHANGES[month]:
				main.type_lever(change[0], change[1])
			await _settle()
			if main.game.pending().size() != CHANGES[month].size():
				_fail("month %d: the interface did not schedule the changes" % month)
				return
		if month == 20:
			main._menu.get_popup().id_pressed.emit(0)
			await _settle()
			saved_hash = main.game.hashes()[19]
		if month == 25:
			main._menu.get_popup().id_pressed.emit(2)
			await _settle()
		next_month.pressed.emit()
		await _settle()
		if main.game.steps_done() != month + 1:
			_fail("month %d: expected %d months done, found %d" % [month, month + 1, main.game.steps_done()])
			return
	var hashes: PackedStringArray = main.game.hashes()
	main.open_indicator("gov_balance")
	await _settle()
	var trace = main.current_trace()
	if trace == null or trace._summary.text.begins_with("Advance") or trace._rows.get_child_count() == 0:
		_fail("the why panel shows nothing for the budget balance")
		return
	main._menu.get_popup().id_pressed.emit(1)
	await _settle()
	if main.game.steps_done() != 20 or main.game.hashes()[19] != saved_hash:
		_fail("loading the save did not restore month 20")
		return
	var lines := PackedStringArray(["step,hash"])
	for i in hashes.size():
		lines.append("%d,%s" % [i, hashes[i]])
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("interface run: %d months, final hash %s" % [hashes.size(), hashes[hashes.size() - 1]])
	quit(0)


func _settle() -> void:
	for i in 3:
		await process_frame
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 3:
		await process_frame


func _fail(message: String) -> void:
	printerr("interface run failed: " + message)
	quit(1)
