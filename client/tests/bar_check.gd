extends SceneTree
## Stage S17.1: the top bar as the window narrows (models/uk/scenarios/2025.toml, three months
## in, so every figure carries its change). At 2560 wide everything shows: every headline
## figure, the search field open, every button's words. Narrowed ten pixels at a time to the
## smallest window (1200), the bar never needs more room than the window has, and what gives
## way does so in the stated order and never out of it: the buttons' words first, then the
## search field to its button, then the figures one at a time in the order of `[play]
## give_way`, and last Add policy's words; approval and political capital never. At 1920
## wide every headline figure still shows. Widened again, everything comes back.
## With the field shut to its button, "/" opens it to type in (a figure gives way to it if
## it must) and Esc shuts it again. With bills waiting that cost more than there is (the
## widest the capital gets) the bar still fits at every width.

const WIDEST := 2560
const ALL_FIGURES := 1920  # every headline figure shows at this width and wider
const NARROWEST := 1200  # the smallest window the project allows (window/size/min_width)

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	root.size = Vector2i(WIDEST, 1440)
	await _frames(6)
	for month in 3:
		for d in main.unanswered_dilemmas():
			main.answer_dilemma(str(d["name"]), 1)
		await _settle()
		main.advance(1)
		await _settle()
	main.report.dismiss()
	await _settle()
	var order: Array = main.play.get("give_way", [])
	if order.is_empty():
		return _fail("the scenario states no order for the figures to give way in")
	var state: Dictionary = main.bar_state()
	if not state["words"] or not state["search"] or not state["hidden"].is_empty() or not state["add_words"]:
		return _fail("at %d wide the bar has given way: %s" % [WIDEST, state])
	if int(ProjectSettings.get_setting("display/window/size/min_width")) != NARROWEST:
		return _fail("the smallest window is %s wide, the check narrows to %d" % [ProjectSettings.get_setting("display/window/size/min_width"), NARROWEST])
	for key in main._chip:
		if not (main._chip[key]["button"] as Control).is_visible_in_tree():
			return _fail("at %d wide %s does not show" % [WIDEST, key])
	# Narrowing: the order of giving way, and the bar inside the window at every width.
	var steps := PackedStringArray()
	var last := {"words": true, "search": true, "hidden": 0}
	for pass_name in ["at rest", "with the capital short"]:
		if pass_name == "with the capital short":
			await _width(WIDEST)
			main.type_lever("basic_rate", 50.0)
			main.type_lever("vat_rate", 35.0)
			main.close_popup()
			await _settle()
			if not main._capital_short:
				return _fail("two large bills did not leave the capital short")
			last = {"words": true, "search": true, "hidden": 0}
		for width in range(WIDEST, NARROWEST - 1, -10):
			await _width(width)
			state = main.bar_state()
			var needs: float = (main._bar.get_child(0) as Control).get_combined_minimum_size().x + main._bar.get_theme_stylebox("panel").get_minimum_size().x
			if needs > width + 0.5 or main._bar.size.x > width + 0.5:
				return _fail("%s at %d wide the bar needs %.0f (it is %.0f wide): %s" % [pass_name, width, needs, main._bar.size.x, state])
			var hidden: PackedStringArray = state["hidden"]
			# The stated order, as far as it has gone; and nothing given back while narrowing.
			if Array(hidden) != order.slice(0, hidden.size()):
				return _fail("%s at %d wide the figures gone are %s, not the first of %s" % [pass_name, width, hidden, order])
			if not hidden.is_empty() and (state["words"] or state["search"]):
				return _fail("%s at %d wide a figure gave way before the words and the search field: %s" % [pass_name, width, state])
			if width >= ALL_FIGURES and not hidden.is_empty():
				return _fail("%s at %d wide a headline figure has given way: %s" % [pass_name, width, hidden])
			if not state["add_words"] and hidden.size() < main._chip.size() - 1:
				return _fail("%s at %d wide Add policy lost its words before the last figure gave way: %s" % [pass_name, width, state])
			if not state["search"] and state["words"]:
				return _fail("%s at %d wide the search field shut before the buttons lost their words" % [pass_name, width])
			if (state["words"] and not last["words"]) or (state["search"] and not last["search"]) or hidden.size() < int(last["hidden"]):
				return _fail("%s narrowing to %d wide something came back: %s after %s" % [pass_name, width, state, last])
			for vital in [main._capital, main._chip[main._approval_key()]["button"]]:
				var rect: Rect2 = (vital as Control).get_global_rect()
				if not (vital as Control).is_visible_in_tree() or rect.position.x < 0.0 or rect.end.x > width:
					return _fail("%s at %d wide approval or capital is not on the bar: %s" % [pass_name, width, rect])
			if pass_name == "at rest":
				if last["words"] and not state["words"]:
					steps.append("the words at %d" % width)
				if last["search"] and not state["search"]:
					steps.append("the search field at %d" % width)
				for i in range(int(last["hidden"]), hidden.size()):
					steps.append("%s at %d" % [main._key_label(hidden[i]), width])
			last = {"words": state["words"], "search": state["search"], "hidden": hidden.size()}
		if pass_name == "at rest" and (last["words"] or last["search"]):
			return _fail("at %d wide nothing had to give way: the check proves nothing (%s)" % [NARROWEST, last])
	main.game.cancel_lever("basic_rate")
	main.game.cancel_lever("vat_rate")
	await _settle()
	# The search field as its button: "/" opens it, Esc shuts it.
	await _width(1366)
	if main.bar_state()["search"] or not main.search.is_button() or main.search.size.x > main.search.BUTTON + 0.5:
		return _fail("at 1366 wide the search field is not its button: %s, %.0f wide" % [main.bar_state(), main.search.size.x])
	var shown_before: int = main.bar_state()["hidden"].size()
	await _key(KEY_SLASH)
	await _frames(6)
	if not main.search.has_focus() or main.search.is_button() or main.search.size.x < main.search.NARROW - 0.5:
		return _fail("\"/\" did not open the search field: focus %s, %.0f wide" % [main.search.has_focus(), main.search.size.x])
	var needs_open: float = (main._bar.get_child(0) as Control).get_combined_minimum_size().x + main._bar.get_theme_stylebox("panel").get_minimum_size().x
	if needs_open > 1366.5:
		return _fail("with the search field open at 1366 the bar needs %.0f" % needs_open)
	var gave: int = main.bar_state()["hidden"].size() - shown_before
	await _key(KEY_ESCAPE)
	await _frames(6)
	if main.search.has_focus() or not main.search.is_button() or main.bar_state()["hidden"].size() != shown_before:
		return _fail("Esc did not shut the search field to its button: %s" % [main.bar_state()])
	# Widened again: everything back.
	await _width(WIDEST)
	state = main.bar_state()
	if not state["words"] or not state["search"] or not state["hidden"].is_empty():
		return _fail("widened to %d the bar has not come back: %s" % [WIDEST, state])
	while main.effects_running:
		await process_frame
	print("top bar: at %d wide every headline figure, the search field and every button's words; narrowed to %d in the stated order and never out of it (%s), every headline figure still there at %d, the bar inside the window at every width, also with the capital short; approval and capital on it throughout; \"/\" opens the search's button (%d figure%s giving way to it at 1366) and Esc shuts it; all back at %d" % [
		WIDEST, NARROWEST, ", ".join(steps), ALL_FIGURES, gave, "" if gave == 1 else "s", WIDEST])
	quit(0)


func _width(width: int) -> void:
	root.size = Vector2i(width, 1440 if width > 1920 else (1080 if width >= 1600 else 768))
	await _frames(4)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = 47 if code == KEY_SLASH and pressed else 0
		event.pressed = pressed
		root.push_input(event)
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
