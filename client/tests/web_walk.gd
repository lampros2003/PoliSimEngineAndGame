extends SceneTree
## Stage S6.1, through the board (stage S13.2). Opens the UK scenario and plays a month;
## finds the shortest chain of the model's own connections from the basic rate of income
## tax to the government's poll rating (the board's reach search); then walks it back from
## the poll rating's popup, following each cause in turn as the "why it moved" list lets a
## player, and checks each step opens that value's popup and Back returns.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	var web = main.board
	if web.consumers_of("basic_rate").is_empty() or not web.inputs_of("basic_rate").is_empty():
		return _fail("the basic rate should feed values and depend on none")
	var path := _path(web, "basic_rate", "government_support")
	if path.is_empty():
		return _fail("no chain from the basic rate to the poll rating")
	main.open_indicator("government_support")
	await _settle()
	var back := path.slice(0, path.size() - 1)
	back.reverse()
	for name in back:
		if not web.inputs_of(main.indicator_card().name_shown if main.indicator_card() != null else "").has(name) and name != "basic_rate":
			return _fail("%s is not an input of %s" % [name, main.indicator_card().name_shown])
		main.indicator_card().follow.emit(name)
		await process_frame
		var shown: String = main.indicator_card().name_shown if main.indicator_card() != null else main.policy_card().key
		if name == "basic_rate":
			if main.popup_kind() != "policy" or main.policy_card().key != "policy:income_tax":
				return _fail("following the basic rate did not open Income tax")
		elif shown != name:
			return _fail("following %s opened %s" % [name, shown])
	main.popup.back()
	await process_frame
	if main.indicator_card() == null or main.indicator_card().name_shown != path[1]:
		return _fail("Back did not return to %s" % path[1])
	print("web: from the basic rate to the poll rating in %d steps, walked back through the popups: %s" % [path.size() - 1, " > ".join(path)])
	quit(0)


## Breadth first over "what depends on it".
func _path(web, from: String, to: String) -> PackedStringArray:
	var came := {from: ""}
	var queue := [from]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at == to:
			var out := PackedStringArray([to])
			while came[out[0]] != "":
				out.insert(0, came[out[0]])
			return out
		for next in web.consumers_of(at):
			if not came.has(next):
				came[next] = at
				queue.append(next)
	return PackedStringArray()


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
