extends SceneTree
## Opens the scenario given by --scenario, plays one month and writes the budget screen
## as the player sees it, one "label,text" line per row, to --out=PATH. tools/check_client.py
## compares the UK's with the published public finances.
##
## Then raises the basic rate of income tax by one point, plays a second month and writes
## every breakdown of the "who gains, who loses" panel, as shown, to --breakdowns=PATH:
## one tab-separated line per row (month, breakdown, group, this month, change, percent).

var main: Control
var breakdown_path := ""


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
		if arg.begins_with("--breakdowns="):
			breakdown_path = arg.substr(13)
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
	if breakdown_path == "":
		quit(0)
		return
	var shown := PackedStringArray(["month\tbreakdown\tgroup\tnow\tchange\tpercent"])
	_dump_breakdowns(shown, 1)
	var refused: String = main.game.set_lever("basic_rate", 0.21)
	if refused != "":
		push_error(refused)
		quit(1)
		return
	await _settle()
	main.advance(1)
	await _settle()
	_dump_breakdowns(shown, 2)
	file = FileAccess.open(breakdown_path, FileAccess.WRITE)
	file.store_string("\n".join(shown) + "\n")
	file.close()
	print("breakdowns of %d lines written" % (shown.size() - 1))
	quit(0)


func _dump_breakdowns(shown: PackedStringArray, month: int) -> void:
	var panel = main.breakdown
	if not panel.visible:
		push_error("the who gains, who loses panel is hidden")
		return
	var choice: OptionButton = panel._choice
	for i in choice.item_count:
		choice.select(i)
		choice.item_selected.emit(i)
		var rows: Array = panel._rows.duplicate()
		if not panel._all_cells.is_empty():
			rows.append({"cells": panel._all_cells})
		for row in rows:
			var cells: Array = row["cells"]
			shown.append("\t".join([str(month), choice.get_item_text(i), cells[0].text, cells[1].text, cells[2].text, cells[3].text]))


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
