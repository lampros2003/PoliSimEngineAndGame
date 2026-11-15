extends SceneTree
## Stage S10.5: a lag through the interface. Valmora with the growth-over-the-year mod
## (models/valmora/scenarios/year_on_year.toml): the catalogue marks the lag and its twelve
## states; the board's search links the lag to output as one lagged input, not the chain;
## after fourteen months the lag holds the second month's output; and its popup's "why it
## moved" shows it as output twelve months before, and follows it to output's popup.

var main: Control
const LAG := "yoy_gdp_a_year_before"


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or not main.entries.has(LAG):
		return _fail("the lag is not in the catalogue")
	if str(main.entries[LAG].get("lag", "")) != LAG or str(main.entries[LAG + "__12"].get("lag", "")) != LAG:
		return _fail("the lag's var and states are not marked")
	if main.entries.has(LAG + "__13"):
		return _fail("a lag of twelve months has more than twelve states")
	var web = main.board
	if web.inputs_of(LAG) != PackedStringArray(["gdp"]) or not web.consumers_of("gdp").has(LAG):
		return _fail("the web does not link the lag to output: %s" % [web.inputs_of(LAG)])
	if web.consumers_of(LAG + "__1").size() > 0 or web.consumers_of("gdp").has(LAG + "__1"):
		return _fail("the web shows the lag's chain of states")
	var outputs := []
	for month in 14:
		main.advance(1)
		await _settle()
		outputs.append(main.game.latest("gdp"))
	if main.game.steps_done() != 14:
		return _fail("%d months ran, not 14" % main.game.steps_done())
	if main.game.latest(LAG) != outputs[1]:
		return _fail("after 14 months the lag holds %s, not the second month's output %s" % [main.game.latest(LAG), outputs[1]])
	main.open_indicator(LAG)
	await _settle()
	var rows: Array = main.current_trace()._rows.get_children()
	if rows.is_empty():
		return _fail("Why shows nothing for the lag")
	var button: Button = rows[0].get_child(0)
	if button.text != "Output (GDP) (12 months before)" or button.disabled:
		return _fail("Why shows the lag's input as %s" % button.text)
	button.pressed.emit()
	await _settle()
	if main.current_trace()._title.text != "Output (GDP)" or main.indicator_card().name_shown != "gdp":
		return _fail("following the lag's input went to %s, not output" % main.current_trace()._title.text)
	print("lag: output a year before is month 2's after 14 months, shown and followed as output 12 months before")
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
