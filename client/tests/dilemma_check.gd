extends SceneTree
## Stage S9.1: a dilemma through the interface. Valmora with the dock strike mod
## (models/valmora/scenarios/dock_strike.toml): asked to run a year, the game stops after
## three months, when the strike opens, and asks; no month runs until it is answered; the
## answer ("Pay the dockers") shows on the strip and raises the government's purchases by a
## fifth from the next month. Then the same in French: the question in the mod's words.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or main.dilemmas.size() != 1:
		return _fail("the dock strike is not in the catalogue: %d dilemmas" % main.dilemmas.size())
	if main.levers._rows.has("dock_strike_walkout"):
		return _fail("the dilemma's lever is in the policy panel")
	var purchases: int = main.game.latest("gov_spending") if main.game.latest("gov_spending") != null else 0
	main.advance(12)
	await _settle()
	if main.game.steps_done() != 3:
		return _fail("a year's run did not stop at the strike: %d months run" % main.game.steps_done())
	purchases = int(main.game.latest("gov_spending"))
	var dialog: AcceptDialog = main.dilemma_dialog
	if dialog == null or not dialog.visible or dialog.title != "Dock strike":
		return _fail("the strike was not put to the player")
	if not main._advance[0].disabled:
		return _fail("the month buttons are on while the strike waits for an answer")
	var ask: Node = main._situation_strip.get_node_or_null("dilemma_dock_strike_walkout")
	if ask == null or not (ask is Button) or (ask as Button).text != "Decide: Dock strike":
		return _fail("the strip does not ask for a decision")
	main.advance(1)
	await _settle()
	if main.game.steps_done() != 3:
		return _fail("a month ran without an answer")
	main.answer_dilemma("dock_strike_walkout", 1)
	await _settle()
	if dialog.visible or main._advance[0].disabled:
		return _fail("the dialog stayed, or the month buttons stayed off, after the answer")
	main.advance(1)
	await _settle()
	if main.game.steps_done() != 4 or main.game.latest("dock_strike_walkout_choice") != 1:
		return _fail("the answer did not take effect: month %d" % main.game.steps_done())
	var now := int(main.game.latest("gov_spending"))
	if now != roundi(purchases * 1.2):
		return _fail("purchases are %d, a fifth above %d is %d" % [now, purchases, roundi(purchases * 1.2)])
	var chip: Node = main._situation_strip.get_node_or_null("dilemma_dock_strike_walkout")
	var text := "" if chip == null else (chip.get_child(0) as Label).text
	if text != "Dock strike: Pay the dockers · until September 2027":
		return _fail("the strip shows %s" % text)
	print("dilemma: the strike stopped a year's run after three months, was asked, and paying the dockers raised purchases a fifth: %s" % text)
	# The same mod in French.
	main.start(main.scenario_path, PackedStringArray(), "fr")
	await _settle()
	if str(main.dilemmas[0]["label"]) != "Grève des dockers" or str(main.dilemmas[0]["options"][0]["label"]) != "Payer les dockers":
		return _fail("the strike is not in French: %s" % main.dilemmas[0])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
