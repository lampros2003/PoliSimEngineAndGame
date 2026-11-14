extends SceneTree
## Plays 60 months through the bridge, making the lever changes listed in
## models/toy/scenarios/client_check.toml interactively, and writes "step,hash" lines to
## the file named by --out=PATH. tools/check_client.py compares them with the runner.

const CHANGES := {
	6: [["basic_rate", 0.25]],
	15: [["gov_purchases", 1550000000]],
	30: [["benefit_rate", 900], ["vat_rate", "0.175"]],
	42: [["personal_allowance", "1,100.50"]],
}


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	var game := PoliSim.new()
	var scenario := _find("models/toy/scenarios/baseline.toml")
	var error := game.open(scenario)
	if error != "":
		_fail("open: " + error)
		return
	for month in range(60):
		if CHANGES.has(month):
			for change in CHANGES[month]:
				var refused: String = game.set_lever(change[0], change[1])
				if refused != "":
					_fail("set %s: %s" % [change[0], refused])
					return
		game.advance(1)
		while game.is_busy():
			OS.delay_msec(1)
		for event in game.poll():
			if event["kind"] == "failed":
				_fail(event["error"])
				return
	# A refused change must be reported, not applied.
	if game.set_lever("vat_rate", 3.0) == "":
		_fail("a VAT rate of 300% was accepted")
		return
	var hashes: PackedStringArray = game.hashes()
	var lines := PackedStringArray(["step,hash"])
	for i in hashes.size():
		lines.append("%d,%s" % [i, hashes[i]])
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("scripted run: %d months, final hash %s" % [hashes.size(), hashes[hashes.size() - 1]])
	quit(0)


func _fail(message: String) -> void:
	printerr("scripted run failed: " + message)
	quit(1)


static func _find(relative: String) -> String:
	var base := ProjectSettings.globalize_path("res://")
	for candidate in [base.path_join(relative), base.path_join("..").path_join(relative)]:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	return base.path_join(relative)
