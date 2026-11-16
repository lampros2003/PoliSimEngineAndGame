extends SceneTree
## Stage S15.1: the Add policy sheet, search and situations on their nodes, through the
## interface (models/uk/scenarios/2025.toml). After a month: no "New policy" node on the
## board; A opens the Add policy sheet, every area lists exactly its policies not in force
## (an area with none greyed); choosing one closes the sheet and opens its popup at its first
## step, ready to put to the Commons; put, it waits on the board as a ghost, and after the
## month it is in force (or the report says why not). "/" focuses search; "strong growth"
## finds the situation and lights the Growth node; "fuel" finds Fuel duty first and Enter opens
## it; Esc clears; a situation's pennant lights its node and opens it with "Set off by"; a
## situation in force flags its node.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1920, 1080)
	await _settle()
	main.advance(1)
	await _settle()
	var board = main.board
	for key in board.order:
		if not board.nodes[key]["kind"] in ["centre", "group", "indicator", "policy"]:
			return _fail("%s is on the board" % key)
	# The sheet, by the key A.
	_key(KEY_A)
	await _settle()
	if not main.add_sheet_open():
		return _fail("A did not open the Add policy sheet")
	var sheet = main.add_list
	var offered := 0
	for area in board.areas:
		var name := str(area["name"])
		sheet.show_area(name)
		var want: PackedStringArray = board.available_in(name)
		var button: Button = sheet._area_buttons[name]
		if sheet.keys != want or button.disabled != want.is_empty():
			return _fail("%s on the sheet: %s, not %s (greyed %s)" % [name, sheet.keys, want, button.disabled])
		offered += want.size()
	if offered != board.available.size() or offered == 0:
		return _fail("the sheet offers %d policies, %d are not in force" % [offered, board.available.size()])
	# Choosing one: its popup at its first step, ready to put to the Commons.
	var key: String = board.available.keys()[0]
	sheet.show_policy(key)
	var row: Button = sheet.rows[key]
	row.pressed.emit()
	await _settle()
	var card = main.policy_card()
	if main.add_sheet_open() or card == null or card.key != key or not card.introducing or card.draft.is_empty() or card.put_button.disabled:
		return _fail("choosing %s: sheet %s, popup %s" % [key, main.add_sheet_open(), main.popup_kind()])
	var lever: String = card.levers[0]
	card.put_button.pressed.emit()
	await _settle()
	if not board.nodes.get(key, {}).get("ghost", false):
		return _fail("%s put to the Commons is not waiting on the board" % key)
	main.advance(1)
	await _settle()
	var fate := Array(main.report.lines_shown).filter(func(l): return str(l).begins_with(str(board.policy_node(key)["label"])))
	var in_force: bool = board.nodes.has(key) and not board.nodes[key].get("ghost", false)
	if fate.is_empty() or in_force != str(fate[0]).contains(" introduced at "):
		return _fail("after the month %s is %s; the report says %s" % [key, "in force" if in_force else "not in force", fate])
	main.report.dismiss()
	# Search: "/", then "strong growth".
	_key(KEY_SLASH)
	await process_frame
	if not main.search.has_focus():
		return _fail("/ did not focus the search")
	var growth: String = main.situation_node("strong_growth")
	var found: Array = main.search_for("strong growth")
	if growth == "" or found.is_empty() or str(found[0]["key"]) != "situation:strong_growth" or board.lit != growth or not board.matches.has(growth):
		return _fail("strong growth: %s; lit %s, the node %s" % [found.map(func(r): return r["key"]), board.lit, growth])
	found = main.search_for("fuel")
	if found.is_empty() or str(found[0]["key"]) != "policy:fuel_duty":
		return _fail("fuel: %s" % [found.map(func(r): return r["key"])])
	_key(KEY_ENTER)
	await _settle()
	if main.popup_kind() != "policy" or main.policy_card().key != "policy:fuel_duty":
		return _fail("Enter on Fuel duty opened %s (steps %d, focus %s)" % [main.popup_kind(), main.game.steps_done(), root.gui_get_focus_owner()])
	main.close_popup()
	main.search.grab_focus()
	main.search_for("unemployment")
	_key(KEY_ESCAPE)
	await process_frame
	if main.search.text != "" or board.searching or main.search.has_focus():
		return _fail("Esc did not clear the search")
	# A pennant lights its node and opens the situation beside it, set off by its statistic.
	main.strip.flag_pressed.emit({"key": "situation_strong_growth", "name": "strong_growth", "tone": "good", "text": "Strong growth"})
	await _settle()
	var explained = main.indicator_card()
	if board.lit != growth or explained == null or explained.name_shown != "strong_growth" or not explained.set_off_text.begins_with(str(board.nodes[growth]["label"])):
		return _fail("the pennant: lit %s, popup %s, set off by %s" % [board.lit, main.popup_kind(), explained.set_off_text if explained != null else ""])
	var set_off: String = explained.set_off_text
	main.close_popup()
	await _settle()
	if board.lit != "":
		return _fail("the node stays lit after its popup closed")
	# A situation in force flags its node.
	main._situations_on["strong_growth"] = true
	main._refresh()
	if not board.node_flags.get(growth, []).has("good"):
		return _fail("strong growth in force does not flag %s: %s" % [growth, board.node_flags])
	print("add and search: no New policy node; A opens the sheet, %d policies to add in %d areas, each area's exact; %s chosen opens at its first step, waits as a ghost, then %s; '/' then 'strong growth' finds the situation and lights %s; 'fuel' finds Fuel duty and Enter opens it; Esc clears; a pennant lights its node, set off by %s; a situation in force flags its node" % [
		offered, board.areas.size(), key, fate[0], growth, set_off])
	while main.effects_running:
		await process_frame
	quit(0)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.unicode = {KEY_SLASH: 47, KEY_A: 97}.get(code, 0)
		root.push_input(event)


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
