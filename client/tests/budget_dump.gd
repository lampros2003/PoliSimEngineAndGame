extends SceneTree
## Opens the scenario given by --scenario, plays one month and writes the budget screen
## as the player sees it, one "label,text" line per row, to --out=PATH. tools/check_client.py
## compares the UK's with the published public finances.

var main: Control


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or main.game.steps_done() != 0:
		push_error("the game did not start")
		quit(1)
		return
	# Inputs marked player = false (world demand, market rates) never reach the policy panel.
	for name in main.levers._rows:
		if not main.entries[name].get("player", true):
			push_error("the input %s is offered to the player" % name)
			quit(1)
			return
	if main.levers._rows.has("export_demand") or not main.levers._rows.has("vat_rate"):
		push_error("the policy panel does not hold the right levers")
		quit(1)
		return
	main.advance(1)
	await _settle()
	var lines := PackedStringArray(["label,text"])
	for line in main.budget._lines:
		var entry: Dictionary = line["entry"]
		lines.append("%s,%s" % [str(entry.get("label", line["name"])), line["cells"][0].text])
	for key in ["revenue", "spending", "balance"]:
		var cells: Array = main.budget._totals.get(key, [])
		if cells.size() == 3:
			lines.append("%s,%s" % [key, cells[0].text])
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("budget of %d lines written" % (lines.size() - 1))
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
