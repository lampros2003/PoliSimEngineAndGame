extends SceneTree
## Stage S13.6: the feel of the game, through the interface (models/uk/scenarios/2025.toml).
## At step 0 (a --scenario game) every figure shows the awaiting state, and every popup kind,
## the Budget and Parliament open with no "nan"; no change too small to show reads as a
## negative nought or "+0.00"; the guide is wanted on a first game from the start screen,
## never with --scenario or headless, and its steps point at real things; a bill refused
## for want of political capital and one passed appear in the month's report, with the
## figures that moved most, and Space ran that month; the links of a node held under the
## pointer while the effects table arrives change at most once (from the formulas' to the
## measured); B, P, Esc and K do their jobs, and Space does nothing in a focused field; a
## game from the start screen opens with its first month played and every figure filled;
## the sound helper asks for its sounds and makes no player headless. Stage S14.1: the refusal
## is told once, in the report, not also in a notice; the report floats over the board, whose
## size it leaves alone, and the date opens it again; K opens the key, drawn by the board's own
## code; Esc closes the report. Stage S14.4: a loaded game has its links on the first hover,
## from the table saved with it, and asks for no other; the report never covers the centre and
## is gone the moment the next month is asked for.

const Format := preload("res://scripts/format.gd")
const Sound := preload("res://scripts/sound.gd")

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	# A window's size, so the board is laid out as on a screen (headless has none).
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1366, 768)
	await _settle()
	var board = main.board
	# Step 0: the awaiting state everywhere, nothing blank or broken.
	if main.game.steps_done() != 0 or not main.awaiting():
		return _fail("a --scenario game should open at step 0")
	if not str(board.centre.get("change", "")).begins_with("Awaiting") or str(board.centre.get("figure", "")) != "–":
		return _fail("the centre at step 0: %s" % [board.centre])
	for key in main._chip:
		var chip: Button = main._chip[key]["button"]
		if chip.get_meta("value").text != "–" or not chip.tooltip_text.contains("Awaiting"):
			return _fail("the top bar's %s at step 0 reads %s" % [key, chip.get_meta("value").text])
	for key in board.keys_of("indicator") + board.keys_of("group"):
		var n: Dictionary = board.nodes[key]
		if str(n["value"]) != "–" or not str(n["change"]).begins_with("awaiting"):
			return _fail("%s at step 0 reads %s %s" % [key, n["value"], n["change"]])
	for key in board.keys_of("policy"):
		if float(board.nodes[key]["fraction"]) < 0.0 and main.entries[board.nodes[key]["levers"][0]].get("has_range", false):
			return _fail("%s has no gauge at step 0" % key)
	for key in ["policy:income_tax", "indicator:gdp", "group:young"]:
		main.open_node(key)
		await _settle()
		var text := _texts(main.popup)
		if not text.contains("awaiting") and key != "policy:income_tax":
			return _fail("%s's popup at step 0 does not say its figures are awaited: %s" % [key, text.left(300)])
		if _has_nan(text):
			return _fail("%s's popup at step 0 shows nan" % key)
		main.close_popup()
	for which in ["budget", "parliament"]:
		main.open_overlay(which)
		await _settle()
		var text := _texts(main._sheets)
		if _has_nan(text):
			return _fail("%s at step 0 shows nan" % which)
		main.close_overlay()
	# Figures too small to show never read as a negative nought or a signed nought.
	var fmt = main.fmt
	for name in main.entries:
		var entry: Dictionary = main.entries[name]
		if str(entry.get("type", "")) == "bool":
			continue
		for v in [-1e-9, -0.00004, -0.0004, 1e-9, 0.00004]:
			for text in [fmt.change(entry, v), fmt.value(entry, v), fmt.value(entry, v, false, false)]:
				if (text.begins_with("-") or text.begins_with("−") or text.begins_with("+")) and Format.is_nought(text):
					return _fail("%s formats %s as %s" % [name, v, text])
		if fmt.change(entry, -1e-9) != "no change":
			return _fail("%s: a tiny change reads %s" % [name, fmt.change(entry, -1e-9)])
	if Format.percent(-0.00001) != "0.0%" and Format.percent(-0.00001) != "0%":
		return _fail("a tiny negative share reads %s" % Format.percent(-0.00001))
	# The guide: wanted on a first game from the start screen only.
	if not main.should_guide(true, false, false) or main.should_guide(false, false, false) or main.should_guide(true, true, false) \
			or main.should_guide(true, false, true):
		return _fail("the guide is wanted in the wrong cases")
	if main.guide.visible:
		return _fail("the guide shows for a --scenario game")
	# The base month, by the keyboard; then a month with a big change: a VAT rate the capital
	# cannot pay for, and a basic rate it can.
	_key(KEY_SPACE)
	await _settle()
	if main.game.steps_done() != 1:
		return _fail("Space did not run the month (%d steps)" % main.game.steps_done())
	main.type_lever("vat_rate", 60.0)
	main.type_lever("basic_rate", 23.0)
	main.close_popup()
	await _settle()
	_key(KEY_ENTER)
	await _settle()
	if main.game.steps_done() != 2:
		return _fail("Enter did not run the month (%d steps)" % main.game.steps_done())
	var lines: PackedStringArray = main.report.lines_shown.duplicate()
	# The capital pays for the first bill in line, and not then for the second.
	var refused := Array(lines).filter(func(l): return l.contains(": refused, it needed"))
	var passed := Array(lines).filter(func(l): return l.ends_with(": passed"))
	var moves := Array(lines).filter(func(l): return l.contains("▲") or l.contains("▼"))
	if not main.report.visible or refused.is_empty() or passed.is_empty() or moves.size() < 3:
		return _fail("the month's report: %s" % [lines])
	if main.notice_text().contains("refused") or main.notice_text().contains("political capital"):
		return _fail("the refusal is told twice: %s" % main.notice_text())
	# The report floats: the board keeps its size and its nodes their places while it is open.
	var board_size: Vector2 = board.size
	var spot: Vector2 = board.nodes["centre"]["pos"]
	main.report.dismiss()
	await _settle()
	if board.size != board_size or board.nodes["centre"]["pos"] != spot:
		return _fail("the board changed with the report: %s to %s" % [board_size, board.size])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._date.gui_input.emit(click)
	if not main.report.visible:
		return _fail("the date did not open the report again")
	var centre_rect := Rect2(board.position + board.nodes["centre"]["pos"] - Vector2.ONE * board.nodes["centre"]["r"], Vector2.ONE * 2.0 * board.nodes["centre"]["r"])
	if main.report.get_rect().intersects(centre_rect):
		return _fail("the report covers the centre: %s and %s" % [main.report.get_rect(), centre_rect])
	_key(KEY_ESCAPE)
	if main.report.visible:
		return _fail("Esc did not close the report")
	if not Sound.asked.has("bill") or not Sound.asked.has("notice"):
		return _fail("sounds asked for: %s" % [Sound.asked])
	# A node held under the pointer while the effects table arrives: one change at most.
	main.hover("policy:income_tax")
	var sets: int = board.link_sets
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 2000 or main.effects_running or not board.effects.has("basic_rate"):
		await process_frame
		if Time.get_ticks_msec() - began > 120000:
			return _fail("the effects table never arrived")
	var changes: int = board.link_sets - sets
	var measured: bool = board._links.all(func(l): return l["measured"])
	if changes > 1 or board._links.is_empty() or not measured:
		return _fail("pointing at Income tax while effects arrived: %d link sets, measured %s" % [changes, measured])
	main.hover("")
	# Stage S14.4: a game saved with its effects table, loaded: the table comes with it, so the
	# links are there on the first hover and nothing is asked for again.
	var saved_to: String = main.save_path
	main.save_path = ProjectSettings.globalize_path("user://feel_check.psave")
	main.save_game()
	await _settle()
	var asked: int = main.effects_requests
	main.load_game()
	await _settle()
	for i in 30:
		await process_frame
	main.hover("policy:income_tax")
	var loaded_links: bool = not board._links.is_empty() and board._links.all(func(l): return l["measured"])
	main.hover("")
	DirAccess.remove_absolute(main.save_path)
	main.save_path = saved_to
	if not loaded_links or main.effects_requests != asked:
		return _fail("a loaded game: measured links on the first hover %s, the table asked for %d more times" % [loaded_links, main.effects_requests - asked])
	# Keys.
	_key(KEY_B)
	if main.overlay_open() != "budget":
		return _fail("B did not open the Budget")
	_key(KEY_ESCAPE)
	if main.overlay_open() != "":
		return _fail("Esc did not close the Budget")
	_key(KEY_P)
	if main.overlay_open() != "parliament":
		return _fail("P did not open Parliament")
	_key(KEY_P)
	main.open_node("indicator:gdp")
	_key(KEY_ESCAPE)
	if main.popup_kind() != "":
		return _fail("Esc did not close the popup")
	_key(KEY_K)
	await _settle()
	var page: Node = main.find_child("key_page", true, false)
	if page == null or not main._key_sheet.visible or page.find_children("*", "Control", true, false).filter(func(c): return c.get("demo") == true).size() < 4:
		return _fail("K did not open the key with the board's own drawings")
	_key(KEY_ESCAPE)
	if main._key_sheet.visible:
		return _fail("Esc did not close the key")
	# Stage S18.2: F11 takes the whole screen, and the menu shows it ticked; F11 again gives the
	# window back (without a display there is no window to change: the setting is what is read).
	var menu: PopupMenu = main._menu.get_popup()
	_key(KEY_F11)
	if not main.fullscreen or not menu.is_item_checked(menu.get_item_index(10)):
		return _fail("F11 did not take the whole screen")
	_key(KEY_F11)
	if main.fullscreen or menu.is_item_checked(menu.get_item_index(10)):
		return _fail("F11 did not give the window back")
	main.open_node("policy:vat")
	await _settle()
	var field: LineEdit = main.policy_card().find_child("lever_vat_rate", true, false)
	field.grab_focus()
	_key(KEY_SPACE)
	await _settle()
	if main.game.steps_done() != 2:
		return _fail("Space in a field ran a month")
	main.close_popup()
	await _settle()
	# The guide's steps point at real things.
	main.show_guide(false)
	var titles := PackedStringArray()
	while main.guide.visible and titles.size() < 8:
		var target: Rect2 = main.guide.target()
		if target.size.x < 10.0 or not Rect2(Vector2.ZERO, main.size).grow(8.0).encloses(target):
			return _fail("the guide's step %s points at %s" % [main.guide.step_title(), target])
		titles.append(main.guide.step_title())
		main.guide.next()
	if titles.size() != 5:
		return _fail("the guide's steps: %s" % [titles])
	main.show_guide(false)
	_key(KEY_ESCAPE)
	if main.guide.visible:
		return _fail("Esc did not skip the guide")
	# The next month closes the report at once, and is asked for at once.
	main.report.reopen()
	var asked_at: int = main.game.steps_done()
	main.advance(1)
	if main.report.visible or not (main.game.is_busy() or main.advance_queued()):
		return _fail("Next month with the report open: report %s, month asked %s" % [main.report.visible, main.game.is_busy()])
	await _settle()
	if main.game.steps_done() != asked_at + 1:
		return _fail("the month after the report did not run")
	# A new game from the start screen: its opening month played, every figure filled.
	main.start_from_screen(main.find_file("models/uk/scenarios/2025.toml"), PackedStringArray(), false)
	await _settle()
	if main.game.steps_done() != 1 or main.guide.visible or main.report.visible:
		return _fail("the start screen's game: %d steps, guide %s, report %s" % [main.game.steps_done(), main.guide.visible, main.report.visible])
	if str(board.centre.get("figure", "–")) == "–" or str(board.centre.get("election", "")) == "" or str(board.centre.get("capital", "")) == "":
		return _fail("the centre after the opening month: %s" % [board.centre])
	for key in main._chip:
		if main._chip[key]["button"].get_meta("value").text == "–":
			return _fail("the top bar's %s is blank after the opening month" % key)
	for key in board.keys_of("indicator") + board.keys_of("group"):
		if str(board.nodes[key]["value"]) == "–" and str(board.nodes[key].get("note", "")) == "":
			return _fail("%s is blank after the opening month" % key)
	if Sound.players() != 0:
		return _fail("a sound player was made in a headless run")
	print("feel: the awaiting state at step 0 everywhere; no negative noughts; the guide only on a first game, its %d steps on real things; Space ran a month whose report lists %d lines (%s); links held steady under the pointer (%d change); the report floats and is told once; B, P, Esc, K and a focused field behave; a start-screen game opens with its first month played; %d sounds asked for, none played headless" % [
		titles.size(), lines.size(), " / ".join(lines.slice(0, 3)), changes, Sound.asked.size()])
	while main.effects_running:
		await process_frame
	quit(0)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.unicode = 32 if code == KEY_SPACE else 0
		root.push_input(event)


## Every word on labels and buttons under a node.
func _texts(node: Node) -> String:
	var out := PackedStringArray()
	for child in node.find_children("*", "", true, false):
		if child is Label or child is Button:
			out.append(str(child.text))
		elif child is RichTextLabel:
			out.append(child.get_parsed_text())
	return " | ".join(out).to_lower()


## "nan" or "inf" as a word of its own: stage S13.8's "The public finances" holds "nan".
func _has_nan(text: String) -> bool:
	var word := RegEx.create_from_string("\\b(nan|inf)\\b")
	return word.search(text) != null


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
