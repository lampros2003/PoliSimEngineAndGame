extends SceneTree
## Stage S5.4: a bill voted down, through the interface. Opens the UK's hung-parliament test
## scenario (an election in the second month leaves the player's centre-left leading a
## coalition without a majority of its own), plays two months, raises the basic rate, plays
## a third, and checks that the House of Commons voted it down 324 to 326: the rate kept its
## value, the change is recorded as defeated with its vote, the player is told, and the
## chart marks nothing. Stage S13.2: through the basic rate's popup on the board.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or not main.catalogue.get("legislature", false):
		return _fail("the game did not start with a legislature")
	main.open_node(main.board.policy_of("basic_rate"))
	if main.policy_card() == null or not main.policy_card().hint.text.begins_with("Changes are bills"):
		return _fail("the policy panel does not say changes are bills")
	main.advance(2)
	await _settle()
	if main.lost:
		return _fail("the player lost office at the election")
	var refused: String = main.game.set_lever("basic_rate", 0.21)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	var changes: Array = main.game.changes()
	if changes.size() != 1 or changes[0]["passed"] or int(changes[0]["votes_for"]) != 324 or int(changes[0]["seats"]) != 650:
		return _fail("the change was not recorded as defeated 324 to 326: %s" % [changes])
	if absf(float(main.game.latest("basic_rate")) - 0.2) > 1e-12:
		return _fail("the basic rate changed although the bill was defeated")
	# Stage S14.1: told once, in the month's report, not also in a notice.
	var told := Array(main.report.lines_shown).filter(func(l): return str(l).contains(": voted down, 324 to 326"))
	if not main.report.visible or told.size() != 1 or main.notice_text().contains("voted down"):
		return _fail("the player was not told once: report %s %s, notice %s" % [main.report.visible, main.report.lines_shown, main.notice_text()])
	main.open_node(main.board.policy_of("basic_rate"))
	await _settle()
	if not main.policy_card().chart.markers.is_empty():
		return _fail("the chart marks a change that never took effect")
	print("bill vote: the basic rate rise was voted down 324 to 326, the rate kept, the player told")
	quit(0)


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
