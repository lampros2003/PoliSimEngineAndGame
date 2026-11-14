extends SceneTree
## Stage S5.4: a bill voted down, through the interface. Opens the UK's early-election test
## scenario (an election in the second month leaves the centre-right leading a coalition),
## plays two months, has the government cut the basic rate, plays a third, and checks that
## the House of Commons voted it down: the rate kept its value, the change is recorded as
## defeated with its vote, the player is told, and the chart marks nothing.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or not main.catalogue.get("legislature", false):
		return _fail("the game did not start with a legislature")
	if not main.levers.hint.text.begins_with("Changes are bills"):
		return _fail("the policy panel does not say changes are bills")
	main.advance(2)
	await _settle()
	var refused: String = main.game.set_lever("basic_rate", 0.18)
	if refused != "":
		return _fail(refused)
	await _settle()
	main.advance(1)
	await _settle()
	var changes: Array = main.game.changes()
	if changes.size() != 1 or changes[0]["passed"] or int(changes[0]["votes_for"]) != 283 or int(changes[0]["seats"]) != 650:
		return _fail("the change was not recorded as defeated 283 to 367: %s" % [changes])
	if absf(float(main.game.latest("basic_rate")) - 0.2) > 1e-12:
		return _fail("the basic rate changed although the bill was defeated")
	if not main._message.visible or not main._message_text.text.contains("voted down"):
		return _fail("the player was not told: %s" % main._message_text.text)
	main._refresh_chart()
	if not main.chart.markers.is_empty():
		return _fail("the chart marks a change that never took effect")
	print("bill vote: the basic rate cut was voted down 283 to 367, the rate kept, the player told")
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
