extends SceneTree
## Stage S12.5: political capital through the interface (models/uk/scenarios/2025.toml).
## After a month the capital shows at the centre of the board; typing a basic rate of
## 22% shows what the bill costs (5 + 60 x 2 x 0.02 = 7.4: stage S13.7 weighs the main tax
## rates 2); two big bills in one month (a 50% basic rate and a 35% VAT, 41 each, with about
## 47 to 54 to spend) leave the second refused, and the player is told. Stage S16.1: the
## capital is on the top bar, readable (inside the window, over every popup's and sheet's veil)
## with a policy popup open and with each sheet open, at 1366x768 and 1920x1080; the popup says
## what a bill would leave; two bills that cost more than there is turn it red and say why.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	if main.failed:
		return _fail("the game did not start")
	if not main.capital_text().begins_with("Political capital "):
		return _fail("the capital reads: " + main.capital_text())
	main.type_lever("basic_rate", 22.0)
	await _settle()
	var pending: String = main.policy_card().pending_text("basic_rate")
	var capital_now := float(main.game.latest("political_capital"))
	if not pending.contains("costs 7.4 political capital, %.1f of %.1f left" % [capital_now - 7.4, capital_now]) or not main.capital_text().ends_with("7.4 for bills waiting"):
		return _fail("the cost reads: %s / %s" % [pending, main.capital_text()])
	var change: Label = main._capital.get_meta("change")
	if change.text != "bills waiting 7.4" or main._capital_short:
		return _fail("the top bar's capital reads %s %s" % [main._capital.get_meta("value").text, change.text])
	# Readable at two sizes with the popup open and with each sheet open.
	for view in [Vector2(1366, 768), Vector2(1920, 1080)]:
		main.set_anchors_preset(Control.PRESET_TOP_LEFT)
		main.size = view
		await _settle()
		for state in ["popup", "budget", "parliament", "add_policy", "key"]:
			match state:
				"popup":
					main.open_node("policy:income_tax")
				"budget", "parliament":
					main.open_overlay(state)
				"add_policy":
					main.open_add_policy()
				"key":
					main.show_key()
			await _settle()
			if not _readable(main._capital, view) or not _readable(main._chip[main._approval_key()]["button"], view):
				return _fail("at %s with the %s open the capital or approval cannot be read" % [view, state])
			main.close_popup()
			main.close_overlay()
			if main._key_sheet != null:
				main._key_sheet.close()
			await _settle()
	main.type_lever("basic_rate", 50.0)
	main.type_lever("vat_rate", 35.0)
	await _settle()
	if not main.policy_card().capital_note.text.contains("more than there is: the bills that come last are refused"):
		return _fail("no warning before the month: " + main.policy_card().capital_note.text)
	var bar_change: Label = main._capital.get_meta("change")
	if not main._capital_short or not bar_change.text.contains(" short") or bar_change.get_theme_color("font_color") != main.Palette.BAD \
			or not main._capital.tooltip_text.contains("more than there is"):
		return _fail("two bills beyond the capital: the top bar reads %s" % bar_change.text)
	main.advance(1)
	await _settle()
	# Stage S14.1: in the month's report, once.
	if not main.report.visible or Array(main.report.lines_shown).filter(func(l): return str(l).contains(": refused, it needed")).size() != 1:
		return _fail("the refusal was not announced: %s" % [main.report.lines_shown])
	if main.game.latest("vat_rate") != 0.2 or main.game.latest("basic_rate") != 0.5:
		return _fail("the rates are %s and %s" % [main.game.latest("basic_rate"), main.game.latest("vat_rate")])
	print("capital: on the top bar beside approval, readable over a popup and every sheet at 1366x768 and 1920x1080; a bill's cost and what it leaves shown before it is made; bills beyond the capital red on the bar with the reason; a bill the government cannot pay for refused and announced")
	quit(0)


## On screen, inside the window, nothing drawn over it but the guide (the top bar is above
## every popup and sheet).
func _readable(c: Control, view: Vector2) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var r := c.get_global_rect()
	if not Rect2(Vector2.ZERO, view).encloses(r) or r.size.x < 30.0:
		return false
	var bar: Control = main._bar
	for other in [main.popup, main._sheets, main.report]:
		if other.get_index() > bar.get_index():
			return false
	return true


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
