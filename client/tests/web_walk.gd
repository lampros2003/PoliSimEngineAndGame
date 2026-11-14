extends SceneTree
## Stage S6.1: the icon web, through the interface. Opens the UK scenario, plays a month,
## puts the basic rate of income tax at the centre of the web, and walks from it to the
## government's poll rating by pressing tiles, along the shortest chain the model's own
## connections allow; checks each tile pressed moves the web, and Back returns.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	var web = main.web
	web.show_value("basic_rate")
	await process_frame
	if web.consumers_of("basic_rate").is_empty() or not web.inputs_of("basic_rate").is_empty():
		return _fail("the basic rate should feed values and depend on none")
	# The shortest chain of consumers from the lever to the poll rating.
	var path := _path(web, "basic_rate", "government_support")
	if path.is_empty():
		return _fail("no chain from the basic rate to the poll rating")
	for name in path.slice(1):
		var tile: Button = web.find_child("tile_" + name, true, false)
		if tile == null:
			return _fail("no tile for %s around %s" % [name, web.center])
		tile.pressed.emit()
		await process_frame
		if web.center != name:
			return _fail("pressing %s left the web at %s" % [name, web.center])
	web._back.pressed.emit()
	await process_frame
	if web.center != path[path.size() - 2]:
		return _fail("Back did not return to %s" % path[path.size() - 2])
	print("web: from the basic rate to the poll rating in %d steps: %s" % [path.size() - 1, " > ".join(path)])
	quit(0)


## Breadth first over "what depends on it", visiting tiles in the order the web shows them.
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
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
