extends Control
## Milestone M2.0: open the toy scenario, run twelve months, show the state hash.

var game: PoliSim
var label: Label


func _ready() -> void:
	label = Label.new()
	label.position = Vector2(40, 40)
	label.add_theme_font_size_override("font_size", 22)
	add_child(label)
	game = PoliSim.new()
	var path := find_file("models/toy/scenarios/baseline.toml")
	var error := game.open(path)
	if error != "":
		label.text = "Could not open %s\n%s" % [path, error]
		return
	game.advance(12)


func _process(_delta: float) -> void:
	if game == null:
		return
	for event in game.poll():
		if event["kind"] == "stepped":
			var hashes: PackedStringArray = game.hashes()
			label.text = "PoliSim engine %s inside Godot %s\n%s: %d months run\nstate hash after month 12:\n%s" % [
				game.engine_version(), Engine.get_version_info().string, game.scenario_name(),
				game.steps_done(), hashes[hashes.size() - 1]]
			print("M2.0 hash ", hashes[hashes.size() - 1])
		elif event["kind"] == "failed":
			label.text = "The run failed: " + event["error"]


## Finds a file shipped next to the project (packaged build) or one level up (repository).
static func find_file(relative: String) -> String:
	var base := ProjectSettings.globalize_path("res://")
	for candidate in [base.path_join(relative), base.path_join("..").path_join(relative)]:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	return base.path_join(relative)
