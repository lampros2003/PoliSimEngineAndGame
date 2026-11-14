extends SceneTree
## Stage S12: the pages, the policy areas, the policy web and the map, through the interface
## (models/uk/scenarios/2025.toml). After a month: every page is there and opens; the
## Policy page lists the UK's eleven areas and an area shows only its own policies; the web
## links Income tax to the budget balance, opens the area to its seven policies with the
## basic rate linked the same way, and pressing an outcome explains it.

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.advance(1)
	await _settle()
	if main.failed:
		return _fail("the game did not start")
	for key in ["policy", "budget", "society", "politics", "web", "map"]:
		main.show_page(key)
		if main.pages.current_tab != main._nav[key]["index"] or not main._nav[key]["button"].button_pressed:
			return _fail("the %s page did not open" % key)
	var pressed: int = main._nav.values().filter(func(n): return n["button"].button_pressed).size()
	if pressed != 1:
		return _fail("%d pages are marked open" % pressed)
	var areas: Array = main.levers.categories()
	if areas.size() != 11 or not areas.has("Income tax"):
		return _fail("the policy areas are %s" % [areas])
	main.levers.open_category("Income tax")
	var shown := 0
	for name in main.levers._rows:
		var row: Control = main.levers._rows[name]["spin"].get_parent().get_parent()
		if row.visible:
			shown += 1
			if str(main.levers._rows[name]["entry"].get("group", "")) != "Income tax":
				return _fail("%s shows under Income tax" % name)
	if shown != 7:
		return _fail("Income tax shows %d policies" % shown)
	var web = main.policy_web
	var balance := str(main.rows["budget_balance"]["name"])
	var area_nodes: int = web.nodes.values().filter(func(n): return n["band"] == 0).size()
	if area_nodes != 11 or not web.is_linked("area:Income tax", balance):
		return _fail("the web has %d areas; Income tax to the budget balance: %s" % [area_nodes, web.is_linked("area:Income tax", balance)])
	web.open_area("Income tax")
	var policies: int = web.nodes.values().filter(func(n): return n["band"] == 0).size()
	if policies != 7 or not web.is_linked("basic_rate", balance):
		return _fail("the Income tax web has %d policies; basic rate to the budget balance: %s" % [policies, web.is_linked("basic_rate", balance)])
	web.nodes[balance]["button"].pressed.emit()
	await _settle()
	if main.trace._title.text != str(main.entries[balance]["label"]):
		return _fail("pressing the budget balance explained: " + main.trace._title.text)
	# Stage S12.6: the map, by region, with London's net income the highest and darkest.
	var map = main.map_panel
	if map.statistics.size() != 3 or map._values.size() != 12 or map.colour_of(map._values[6]) != map.colour_of(map._highest()):
		return _fail("the map has %d statistics and %d tiles" % [map.statistics.size(), map._values.size()])
	print("pages: six pages open one at a time; eleven policy areas; the web links Income tax and the basic rate to the budget balance, and explains it when pressed; the map shows twelve regions, London darkest")
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
