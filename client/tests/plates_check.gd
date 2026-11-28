extends SceneTree
## Stage S18.2 and S18.3: the game's own pictures (models/uk/scenarios/2025.toml). The game
## has an icon and an opening picture, of a size to be seen. Every pictogram in client/icons
## has its line in the credits there, and the credits name no file that is gone. Every
## question the model can put, election night won and lost, and the end of a term has a plate
## in the scenario's `[play.plates]`, and the table names no question the model has not; each
## plate's pictograms are in client/icons and its tone is one a plate is printed in. A
## question with no plate of its own (a mod's) falls back to the plain one. The first question
## put to the player carries its plate at the head of its sheet, the sheet's width across,
## with every pictogram on the sheet made at the size it is shown; and the month's report is
## drawn under the sheets, so it never lies over a question or election night.

const Plate := preload("res://scripts/plate.gd")
const Palette := preload("res://scripts/palette.gd")
const OTHERS := ["election", "election_lost", "term"]

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	root.size = Vector2i(1366, 768)
	await _frames(6)
	# The game's icon and opening picture.
	var sizes := PackedStringArray()
	for item in [["application/config/icon", 256, 256], ["application/boot_splash/image", 400, 200]]:
		var path := str(ProjectSettings.get_setting(item[0], ""))
		if path == "" or not FileAccess.file_exists(path):
			return _fail("%s names no file: '%s'" % [item[0], path])
		var picture := Image.load_from_file(ProjectSettings.globalize_path(path))
		if picture == null or picture.get_width() < int(item[1]) or picture.get_height() < int(item[2]):
			return _fail("%s is under %d by %d" % [path, item[1], item[2]])
		sizes.append("%s %d by %d" % [path.get_file(), picture.get_width(), picture.get_height()])
	# The credits: a line for every pictogram, and no line for one that is gone.
	var credits := FileAccess.get_file_as_string("res://icons/CREDITS.md")
	var pictograms := 0
	for file in DirAccess.get_files_at("res://icons"):
		if file.ends_with(".svg"):
			pictograms += 1
			if not credits.contains("| `%s` |" % file):
				return _fail("client/icons/%s has no line in the credits" % file)
	var named := RegEx.create_from_string("(?m)^\\| `([^`]+\\.svg)` \\|")
	for found in named.search_all(credits):
		if not FileAccess.file_exists("res://icons/" + found.get_string(1)):
			return _fail("the credits name %s, which is not in client/icons" % found.get_string(1))
	# The scenario's plates.
	var plates: Dictionary = main.play.get("plates", {})
	var questions := PackedStringArray()
	for d in main.dilemmas:
		questions.append(str(d["name"]))
	if questions.is_empty():
		return _fail("the model puts no questions")
	for key in plates:
		if not key in questions and not key in OTHERS:
			return _fail("a plate for %s, which is no question of the model's" % key)
	for name in Array(questions) + OTHERS:
		if not plates.has(name):
			return _fail("%s has no plate" % name)
		var spec: Variant = plates[name]
		var said: Dictionary = spec if spec is Dictionary else {"icon": str(spec)}
		for picture in [said.get("icon", "")] + Array(said.get("beside", [])):
			if str(picture) == "" or not ResourceLoader.exists("res://icons/%s.svg" % picture):
				return _fail("%s's plate names a pictogram that is not in client/icons: '%s'" % [name, picture])
		if said.has("tone") and not Plate.TONES.has(str(said["tone"])):
			return _fail("%s's plate is in a tone no plate is printed in: %s" % [name, said["tone"]])
		var made: Control = main.plate_for(name, "podium", "ochre")
		var right: bool = made.icon == str(said["icon"]) and made.tone == Plate.TONES[str(said.get("tone", "ochre"))] and Array(made.beside) == Array(said.get("beside", []))
		made.free()
		if not right:
			return _fail("%s's plate is not made as the scenario gives it" % name)
	var plain: Control = main.plate_for("no_such_question", "podium", "ochre")
	var fell_back: bool = plain.icon == "podium" and plain.tone == Palette.OCHRE and plain.beside.is_empty()
	plain.free()
	if not fell_back:
		return _fail("a question with no plate of its own does not get the plain one")
	# The first question put.
	for month in 36:
		if not main.unanswered_dilemmas().is_empty():
			break
		main.advance(1)
		await _settle()
		main.report.dismiss()
	if main.unanswered_dilemmas().is_empty():
		return _fail("no question was put in three years")
	var asked := str(main.unanswered_dilemmas()[0]["name"])
	main.ask_dilemma()
	await _frames(30)
	var sheet: Control = main.dilemma_dialog
	if sheet == null or not sheet.visible or sheet.body.get_child_count() == 0:
		return _fail("the question's sheet did not open")
	var plate := sheet.body.get_child(0) as Control
	if plate == null or plate.get_script() != Plate or not plate.is_visible_in_tree():
		return _fail("the question's sheet does not begin with its plate")
	if plate.icon != str(plates[asked]["icon"]):
		return _fail("%s is shown with the plate of %s" % [asked, plate.icon])
	if plate.size.y < Plate.HEIGHT - 0.5 or plate.size.x < sheet.body.size.x - 1.0 or plate.size.x < 400.0:
		return _fail("the plate is %s on a sheet %s wide" % [plate.size, sheet.body.size.x])
	var card: Rect2 = sheet.card.get_global_rect()
	if not card.encloses(plate.get_global_rect()):
		return _fail("the plate (%s) is not inside its sheet (%s)" % [plate.get_global_rect(), card])
	# Nothing of the month's report lies over a sheet: it is drawn before them.
	if main.report.get_parent() != main._sheets.get_parent() or main.report.get_index() > main._sheets.get_index():
		return _fail("the month's report is drawn over the sheets")
	var soft := Palette.unsharp(sheet)
	if not soft.is_empty():
		return _fail("on the question's sheet: %s" % ", ".join(soft))
	main.answer_dilemma(asked, 1)
	await _settle()
	while main.effects_running:
		await process_frame
	print("plates: %s; %d pictograms, each with its line in the credits; a plate for each of the model's %d questions, for election night won and lost and for the end of a term, every pictogram of theirs in client/icons; the plain plate for a question without one; %s put with its plate at the head of its sheet, %d by %d" % [
		", ".join(sizes), pictograms, questions.size(), asked, int(plate.size.x), int(plate.size.y)])
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


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
