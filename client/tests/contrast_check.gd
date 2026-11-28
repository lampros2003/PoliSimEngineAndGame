extends SceneTree
## Stage S17.1: contrast, measured (WCAG 2.1). First the pairs: every ink the scripts draw
## words or meaning in against the ground it stands on (scripts/contrast.gd, `pairs`), text
## at 4.5 to 1, text of 18 px or more and marks that carry meaning at 3 to 1. Then the
## screens tests/folds_check.gd does not open, each walked as it stands and every piece of
## text in it measured against what is under it: the start screen; the top bar and the strip
## under it at rest, after months have moved the figures, with bills waiting that cost more
## than there is, and with a problem announced; the search's matches; the first-game guide.
## Run without --scenario: it starts the first country on the start screen itself.

const Contrast := preload("res://scripts/contrast.gd")

var main: Control
var _faults := PackedStringArray()


func _initialize() -> void:
	var pairs := Contrast.pairs()
	var closest := ["", 99.0]
	for pair in pairs:
		var got := Contrast.ratio(pair[1], pair[2])
		if got + 0.005 < float(pair[3]):
			_faults.append("%s: #%s on #%s is %.2f to 1, under %.1f" % [pair[0], (pair[1] as Color).to_html(false), (pair[2] as Color).to_html(false), got, pair[3]])
		if got / float(pair[3]) < float(closest[1]):
			closest = ["%s, %.2f against %.1f" % [pair[0], got, pair[3]], got / float(pair[3])]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	root.size = Vector2i(1366, 768)
	for i in 6:
		await process_frame
	if Vector2i(root.get_visible_rect().size) != Vector2i(1366, 768):
		return _fail("the window is %s, not 1366x768" % [root.get_visible_rect().size])
	if main.start_screen == null or main.started:
		return _fail("the start screen is not shown (run without --scenario)")
	await _walk("the start screen", main.start_screen)
	main.start_screen._new.pressed.emit()
	await _settle()
	if not main.started:
		return _fail("the game did not start: %s" % main.notice_text())
	await _walk("the top bar at the start", main._bar)
	for month in 3:
		for d in main.unanswered_dilemmas():
			main.answer_dilemma(str(d["name"]), 1)
		await _settle()
		main.advance(1)
		await _settle()
	main.report.dismiss()
	await _settle()
	await _walk("the top bar after three months", main._bar)
	await _walk("the strip", main.strip)
	# Bills that cost more than there is: the capital in red.
	main.type_lever("basic_rate", 50.0)
	main.type_lever("vat_rate", 35.0)
	main.close_popup()
	await _settle()
	if not main._capital_short:
		return _fail("two large bills did not leave the capital short")
	await _walk("the top bar with the capital short", main._bar)
	main.game.cancel_lever("basic_rate")
	main.game.cancel_lever("vat_rate")
	await _settle()
	main._show_message("[b]Could not load[/b]: the save file is from a newer version of the game.", true)
	await _settle()
	await _walk("the strip with a problem", main.strip)
	main.search_for("tax")
	await _settle()
	if not main.search.results.visible:
		return _fail("the search showed no matches")
	await _walk("the search's matches", main.search.results)
	await _walk("the top bar while searching", main._bar)
	main.search.clear_search()
	main.search.release_focus()
	await _settle()
	main.show_guide(false)
	await _settle()
	for i in 30:
		await process_frame
	await _walk("the guide", main.guide)
	main.guide.visible = false
	while main.effects_running:
		await process_frame
	if not _faults.is_empty():
		for line in _faults:
			push_error(line)
		print("contrast: %d faults" % _faults.size())
		quit(1)
		return
	print("contrast: %d pairs of ink and ground at 4.5 to 1 for text and 3 to 1 for large text and marks (the closest: %s); the start screen, the top bar in four states, the strip, the search's matches and the guide measured as they stand" % [pairs.size(), closest[0]])
	quit(0)


## Measures what is under `under`, once anything fading in has finished.
func _walk(what: String, under: Control) -> void:
	var until := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < until:
		await process_frame
	for line in Contrast.faults(under):
		_faults.append("%s: %s" % [what, line])
	# Stage S18.1: and every pictogram in it made at the size it is shown at.
	for line in Contrast.Palette.unsharp(under):
		_faults.append("%s: %s" % [what, line])


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
