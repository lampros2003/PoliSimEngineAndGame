extends SceneTree
## Stage S17.1: the keyboard, walked through every popup and sheet on the real bridge
## (models/uk/scenarios/2025.toml): a policy, a statistic, a group of voters and a situation;
## The Budget, Parliament, Add policy, the key, help; a question put to the player. With
## Next month holding the keyboard, each is opened and Tab pressed once for every control in
## it: the keyboard goes into the card, visits each control once in the order the card is
## built (never up and to the left at once), stays inside (the press after the last returns
## to the first; Shift+Tab goes back), and each control that holds it shows a ring that can
## be seen (2 px, 3 to 1 against the ground round it). Esc then closes the card and Next
## month has the keyboard again (a question too: it waits on the strip, and no month runs
## until it is answered).

const Focus := preload("res://scripts/focus.gd")

var main: Control
var _home: Control
var _walked := PackedStringArray()
var _controls := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	root.size = Vector2i(1366, 768)
	await _frames(6)
	main.advance(1)
	await _settle()
	main.report.dismiss()
	_home = main._advance[0]
	var situation := ""
	for entry in main.situations:
		situation = str(entry["name"])
		if main.game.latest(str(entry["row"])) == true:
			break
	var layers := [
		["a policy", func() -> void: main.open_node("policy:income_tax"), func() -> Control: return main.popup.card, func() -> bool: return main.popup.is_open()],
		["a statistic", func() -> void: main.open_node("indicator:unemployment_rate"), func() -> Control: return main.popup.card, func() -> bool: return main.popup.is_open()],
		["a group of voters", func() -> void: main.open_node("group:pensioner"), func() -> Control: return main.popup.card, func() -> bool: return main.popup.is_open()],
		["a situation", func() -> void: main.open_situation(situation), func() -> Control: return main.popup.card, func() -> bool: return main.popup.is_open()],
		["The Budget", func() -> void: main.open_overlay("budget"), func() -> Control: return main._budget_sheet.card, func() -> bool: return main._budget_sheet.visible],
		["Parliament", func() -> void: main.open_overlay("parliament"), func() -> Control: return main._parliament_sheet.card, func() -> bool: return main._parliament_sheet.visible],
		["Add policy", func() -> void: main.open_add_policy(), func() -> Control: return main._add_sheet.card, func() -> bool: return main.add_sheet_open()],
		["the key", func() -> void: main.show_key(), func() -> Control: return main._key_sheet.card, func() -> bool: return main._key_sheet.visible],
		["help", func() -> void: main.menu_action("help"), func() -> Control: return main._dialog.card, func() -> bool: return main._dialog != null and is_instance_valid(main._dialog) and main._dialog.visible],
	]
	for layer in layers:
		var problem: String = await _walk(layer[0], layer[1], layer[2], layer[3], true)
		if problem != "":
			return _fail(problem)
	# A popup opened from a sheet: Esc closes the popup first and the keyboard is back on the
	# line that opened it; Esc again closes the sheet.
	_home.grab_focus()
	main.open_overlay("budget")
	await _opened()
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	var line := root.gui_get_focus_owner()
	if line == null or not main._budget_sheet.card.is_ancestor_of(line):
		return _fail("The Budget: the second Tab is on %s" % [line])
	line.pressed.emit()
	await _opened()
	if not main.popup.is_open():
		return _fail("a line of The Budget (%s) opened no popup" % [line.name])
	await _key(KEY_ESCAPE)
	await _frames(6)
	if main.popup.is_open() or not main._budget_sheet.visible or root.gui_get_focus_owner() != line:
		return _fail("Esc over a popup on The Budget: popup open %s, sheet open %s, the keyboard on %s" % [main.popup.is_open(), main._budget_sheet.visible, root.gui_get_focus_owner()])
	await _key(KEY_ESCAPE)
	await _frames(6)
	if main._budget_sheet.visible or root.gui_get_focus_owner() != _home:
		return _fail("Esc on The Budget: sheet open %s, the keyboard on %s" % [main._budget_sheet.visible, root.gui_get_focus_owner()])
	# A question put to the player: months played until one comes.
	var asked := false
	for month in 14:
		if not main.unanswered_dilemmas().is_empty():
			asked = true
			break
		main.advance(1)
		await _settle()
		main.report.dismiss()
	if asked:
		if main.dilemma_dialog != null and is_instance_valid(main.dilemma_dialog):
			main.dilemma_dialog.close()  # put again below, with Next month holding the keyboard
			await _frames(4)
		var problem: String = await _walk("a question", func() -> void: main.ask_dilemma(), func() -> Control: return main.dilemma_dialog.card,
			func() -> bool: return main.dilemma_dialog != null and is_instance_valid(main.dilemma_dialog) and main.dilemma_dialog.visible, true)
		if problem != "":
			return _fail(problem)
		for d in main.unanswered_dilemmas():
			main.answer_dilemma(str(d["name"]), 1)
		await _settle()
	while main.effects_running:
		await process_frame
	print("focus: Tab through %s: %d controls, each reached once in the order its card is built, ringed, and never left for the board; Shift+Tab back; Esc closes each and Next month has the keyboard again; a popup over The Budget closes first, back to its line; a question %s" % [
		", ".join(_walked), _controls, "walked the same way" if asked else "did not come in 14 months"])
	quit(0)


## Opens one card with Next month holding the keyboard and walks it; "" or what is wrong.
func _walk(what: String, open: Callable, card_of: Callable, is_open: Callable, closes: bool) -> String:
	_home.grab_focus()
	await _frames(2)
	if root.gui_get_focus_owner() != _home:
		return "%s: Next month could not take the keyboard" % what
	open.call()
	await _opened()
	if not is_open.call():
		return "%s did not open" % what
	var card: Control = card_of.call()
	var owner := root.gui_get_focus_owner()
	if owner == null or (owner != card and not card.is_ancestor_of(owner)):
		return "%s: opened, the keyboard is still on %s" % [what, owner]
	var list: Array = Focus.order(card)
	if list.is_empty():
		return "%s: nothing in it can be reached by the keyboard" % what
	if owner != card:
		card.grab_focus()  # a card that puts the keyboard on one of its rows: walked from the top all the same
	var before: Control = null
	for k in list.size():
		await _key(KEY_TAB)
		var now := root.gui_get_focus_owner()
		if now != list[k]:
			return "%s: Tab %d is on %s, not %s" % [what, k + 1, _name(card, now), _name(card, list[k])]
		if not Focus.ringed(now):
			return "%s: %s holds the keyboard and shows no ring" % [what, _name(card, now)]
		if before != null:
			var a := before.get_global_rect()
			var b := now.get_global_rect()
			if b.get_center().y < a.position.y - 2.0 and b.get_center().x < a.position.x - 2.0:
				return "%s: from %s the keyboard goes up and to the left, to %s" % [what, _name(card, before), _name(card, now)]
		before = now
	_controls += list.size()
	await _key(KEY_TAB)
	if root.gui_get_focus_owner() != list[0]:
		return "%s: Tab after the last control is on %s, not back at the first" % [what, _name(card, root.gui_get_focus_owner())]
	await _key(KEY_TAB, true)
	if root.gui_get_focus_owner() != list[-1]:
		return "%s: Shift+Tab from the first control is on %s, not the last" % [what, _name(card, root.gui_get_focus_owner())]
	await _key(KEY_ESCAPE)
	await _frames(6)
	if closes:
		if is_open.call():
			return "%s: Esc did not close it" % what
		if root.gui_get_focus_owner() != _home:
			return "%s: closed, the keyboard is on %s, not back on Next month" % [what, root.gui_get_focus_owner()]
	elif not is_open.call():
		return "%s: Esc closed it unanswered" % what
	_walked.append("%s (%d)" % [what, list.size()])
	return ""


func _name(card: Control, control: Control) -> String:
	if control == null:
		return "nothing"
	var words := str(control.get("text")) if control.get("text") != null else ""
	return "%s \"%s\"" % [control.get_class(), words.left(24)] if words != "" else (str(card.get_path_to(control)).right(40) if card.is_ancestor_of(control) else str(control.name))


## A key pressed and let go, as from the keyboard.
func _key(code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.shift_pressed = shift
		root.push_input(event)
	await process_frame


func _opened() -> void:
	await _settle()
	var until := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < until:
		await process_frame


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
