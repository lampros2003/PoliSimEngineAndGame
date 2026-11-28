extends SceneTree
## Stage S18.4: the country as a map (models/uk/scenarios/2025.toml, one month in). The
## scenario names a map and it reads: twelve regions, every one of which can be filled, with
## the acknowledgement its publisher asks for. Every place of the scenario is made of regions
## the map has, and every region of the map belongs to exactly one place, so no land is left
## untinted. The bands of the key grow darker in even steps a reader can tell apart. On the
## Parliament sheet at 1366 by 768 and at 1920 by 1080 the map stands beside the House, the
## land and its key inside the sheet; a point inside each place is found to be that place;
## each place is printed in the band of its own figure, and the one place with no figure is
## hatched. The pointer on a place marks it out on the map and, with the section open, in the
## table; a press opens the section; the pointer off the land marks nothing. How to play
## carries the acknowledgement. A map that cannot be read leaves the table alone, and says why.

const Contrast := preload("res://scripts/contrast.gd")
const CountryMap := preload("res://scripts/country_map.gd")

## Each band against the next, as a ratio of luminance: enough to tell two neighbours apart.
const STEP := 1.3

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	root.size = Vector2i(1366, 768)
	await _frames(6)
	main.advance(1)
	await _settle()
	main.report.dismiss()
	await _settle()
	var web: Dictionary = main.play.get("web", {})
	var places: Array = web.get("places", [])
	if str(web.get("map", "")) == "" or places.is_empty():
		return _fail("the scenario names no map, or no places")
	var map: Control = main.politics.place_map
	if not map.visible or map.error != "":
		return _fail("the map is not shown: %s" % map.error)
	if not map.faults.is_empty():
		return _fail("regions that cannot be filled: %s" % ", ".join(map.faults))
	if map.codes().size() != 12:
		return _fail("%d regions, not twelve" % map.codes().size())
	for words in ["Office for National Statistics", "Open Government Licence", "OS data © Crown copyright"]:
		if not map.source.contains(words):
			return _fail("the map's acknowledgement lacks \"%s\": %s" % [words, map.source])
	# Places and regions: each region in exactly one place.
	var owners := {}
	for i in places.size():
		var regions: Array = places[i].get("regions", [])
		if regions.is_empty():
			return _fail("%s has no regions on the map" % places[i].get("label", ""))
		for code in regions:
			if not str(code) in map.codes():
				return _fail("%s names a region the map has not: %s" % [places[i].get("label", ""), code])
			if owners.has(str(code)):
				return _fail("region %s is in two places" % code)
			owners[str(code)] = i
	for code in map.codes():
		if not owners.has(code):
			return _fail("region %s (%s) is in no place" % [code, map.region_name(code)])
	# The key's bands: each darker than the last, by a step a reader can tell.
	var steps := PackedStringArray()
	for i in range(1, CountryMap.BANDS.size()):
		var lighter := Contrast.luminance(CountryMap.band_colour(i - 1))
		var darker := Contrast.luminance(CountryMap.band_colour(i))
		var step := (lighter + 0.05) / (darker + 0.05)
		if step < STEP:
			return _fail("band %d is %.2f to 1 against band %d, under %.1f" % [i + 1, step, i, STEP])
		steps.append("%.2f" % step)
	if Contrast.ratio(CountryMap.band_colour(0), Contrast.Palette.INK) < Contrast.LARGE:
		return _fail("the lightest band is under 3 to 1 against the ink of the coast")
	# On the sheet, at both sizes.
	var silent := 0
	for size in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
		root.size = size
		await _frames(6)
		main.open_overlay("parliament")
		await _frames(30)
		var card: Rect2 = main._parliament_sheet.card.get_global_rect()
		var land := Rect2(map.get_global_rect().position + map.land().position, map.land().size)
		var whole := Rect2(land.position, land.size + Vector2(0, CountryMap.KEY_HEIGHT + 14.0))
		if not map.is_visible_in_tree() or not card.encloses(whole) or whole.end.y > size.y:
			return _fail("at %s the map and its key (%s) are not inside the sheet (%s)" % [size, whole, card])
		if land.size.x < 150.0:
			return _fail("at %s the land is %.0f px across" % [size, land.size.x])
		silent = 0
		for i in places.size():
			var at: Vector2 = map.point_in(i)
			if map.place_at(at) != i:
				return _fail("at %s a point inside %s is found to be place %d" % [size, places[i].get("label", ""), map.place_at(at)])
			var now: Variant = main.game.latest(str(places[i].get("row", "")))
			var place: Dictionary = map.places[i]
			if bool(place["silent"]):
				silent += 1
				if absf(float(now)) > 0.0005:
					return _fail("%s is hatched though %s back the government there" % [place["label"], now])
			elif place["value"] == null or absf(float(place["value"]) - float(now)) > 1e-9:
				return _fail("%s is printed for %s, the model says %s" % [place["label"], place["value"], now])
		if silent != 1:
			return _fail("%d places are hatched, not the one where the governing party does not stand" % silent)
		# The pointer on a place, a press, and the pointer off the land.
		var north := -1
		for i in places.size():
			if str(places[i].get("label", "")) == "The North":
				north = i
		var spot: Vector2 = map.get_global_rect().position + map.point_in(north)
		await _move(spot)
		if map.chosen != north or main.politics.place_chosen != north:
			return _fail("at %s the pointer on the North marks out %d on the map, %d in the table" % [size, map.chosen, main.politics.place_chosen])
		if main.politics._places.is_visible_in_tree():
			return _fail("the places' table is open before the map is pressed")
		await _press(spot)
		await _frames(8)
		if not main.politics._places.is_visible_in_tree() or main.politics._groups.is_visible_in_tree():
			return _fail("at %s a press on the map did not open the country by place alone" % [size])
		await _move(map.get_global_rect().position + Vector2(map.size.x - 3.0, 3.0))
		if map.chosen != -1 or main.politics.place_chosen != -1:
			return _fail("at %s the pointer off the land still marks out %d" % [size, map.chosen])
		# The table's row marks the map.
		var row: Control = main.politics._place_rows[north]["name"]
		if size.y > 800:
			await _move(row.get_global_rect().get_center())
			if map.chosen != north:
				return _fail("at %s the pointer on the North's row marks out %d on the map" % [size, map.chosen])
		main.politics._open_fold(main.politics._stances_fold)
		main.close_overlay()
		await _frames(8)
	if not main.map_credit().contains(map.source):
		return _fail("How to play does not carry the map's acknowledgement")
	# A map that cannot be read: the table alone, and why.
	main.politics._build_map("../map/none.geojson", main.scenario_path.get_base_dir(), places)
	if map.visible or map.error == "" or main.map_credit() != "":
		return _fail("a map that is not there is shown, or nothing says why not: '%s'" % map.error)
	main.politics._build_map(str(web["map"]), main.scenario_path.get_base_dir(), places)
	if not map.visible:
		return _fail("the map did not come back: %s" % map.error)
	while main.effects_running:
		await process_frame
	print("map: %d regions in %d places, every region in one place and every one filled; bands %s to 1 apart; on the Parliament sheet at 1366 by 768 and 1920 by 1080 the land and its key inside the sheet, a point in each place found there, each place in the band of its figure and %d hatched; the pointer marks a place on the map and in the table, a press opens the table, the pointer off the land marks none; the acknowledgement in How to play; a map not there leaves the table alone" % [
		map.codes().size(), places.size(), ", ".join(steps), silent])
	quit(0)


func _move(to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	root.push_input(event)
	await _frames(3)


func _press(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
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
