extends Control
## Stage S18.4: the country as a map, in the manner of a printed statistical map: the land in
## flat tints of one ink, darker where the figure is higher, an ink coast, a hard shadow under
## the land, and a key of the bands beneath. Each place the scenario names ([play.web] places)
## is one or more of the map's regions, printed as one piece: the lines between two regions of
## one place are not drawn.
##
## The map is read from a GeoJSON file the scenario names ([play.web] map, a path from the
## scenario's own folder): polygons, each with a `code`, and the lines between and around
## them, each with the codes either side (`a` and `b`, `b` empty on the coast). The open tool
## mapshaper writes both from any boundary file (docs/MODDING.md, "A map of the country");
## the United Kingdom's is the Office for National Statistics' regions (models/uk/map).
## Coordinates are a flat grid with north up, in any unit.

const Palette := preload("res://scripts/palette.gd")
const Format := preload("res://scripts/format.gd")

## The lower edge of each band of the figure, and the top of the scale. Five bands of one hue.
const BANDS := [0.0, 0.1, 0.2, 0.3, 0.4]
const TOP := 0.5
## The height the key takes beneath the land, and the least size the map is drawn at (the
## United Kingdom at 202 px across is 374 tall).
const KEY_HEIGHT := 56.0
const LEAST := Vector2(210, 438)

## The pointer came onto a place (its index in `places`), or left the land (-1); a place was
## pressed.
signal place_entered(index: int)
signal place_pressed(index: int)

## Why the file could not be read, or "". What the file says of its source.
var error := ""
var source := ""
## Rings that could not be cut into triangles, so are left unfilled: for the check.
var faults := PackedStringArray()
## The places: {label, regions: [codes], value (a share, or null), silent, note}.
var places: Array = []
## The place marked out (under the pointer, or its row in the table beside): -1 for none.
var chosen := -1:
	set(value):
		if chosen != value:
			chosen = value
			queue_redraw()
## What the figure is, for the key and the words under the pointer.
var measure := "Backing the government"

var _regions := {}  # code -> {name, rings: [PackedVector2Array]}: in the file's units, north at the top; only rings that can be filled
var _lines: Array = []  # {a, b, points}
var _bounds := Rect2()
var _laid_for := Vector2(-1, -1)
var _rings := {}  # code -> [PackedVector2Array] on the control
var _paths: Array = []  # {a, b, points} on the control
var _land := Rect2()


func _init() -> void:
	name = "map"
	custom_minimum_size = LEAST
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		if chosen != -1:
			chosen = -1
			place_entered.emit(-1))


## The tint of band `i`: card stock with more and more of the blue ink, the last the ink itself.
static func band_colour(i: int) -> Color:
	return Palette.CARD.lerp(Palette.BLUE, lerpf(0.16, 1.0, float(clampi(i, 0, BANDS.size() - 1)) / float(BANDS.size() - 1)))


## The band a figure falls in.
static func band_of(value: float) -> int:
	var band := 0
	for i in BANDS.size():
		if value >= float(BANDS[i]):
			band = i
	return band


## Reads the map at `path`. Returns "" or why it could not be read (also kept in `error`).
func read(path: String) -> String:
	_regions.clear()
	_lines.clear()
	faults.clear()
	_laid_for = Vector2(-1, -1)
	error = ""
	if not FileAccess.file_exists(path):
		error = "no file at %s" % path
		return error
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("features") is Array:
		error = "%s is not a GeoJSON collection of features" % path.get_file()
		return error
	source = str((parsed as Dictionary).get("attribution", ""))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for feature in (parsed as Dictionary)["features"]:
		if not feature is Dictionary or not feature.get("geometry") is Dictionary:
			continue
		var said: Dictionary = feature.get("properties", {}) if feature.get("properties") is Dictionary else {}
		var kind := str(feature["geometry"].get("type", ""))
		var coordinates: Variant = feature["geometry"].get("coordinates", [])
		if not coordinates is Array:
			continue
		if kind == "Polygon" or kind == "MultiPolygon":
			var code := str(said.get("code", ""))
			if code == "":
				continue
			var rings: Array = _regions.get(code, {}).get("rings", [])
			# A polygon's first ring is its edge; any others are holes in it, which a map of
			# regions that cover the land fills with another region, so they are passed over.
			for polygon in ([coordinates] if kind == "Polygon" else coordinates):
				if polygon is Array and not (polygon as Array).is_empty():
					var ring := _points(polygon[0])
					if ring.size() >= 2 and ring[0] == ring[-1]:
						ring.remove_at(ring.size() - 1)
					if ring.size() < 3:
						continue
					if Geometry2D.triangulate_polygon(ring).is_empty():
						# Left unfilled (the lines round it still draw); the check holds that
						# the game's own map has none.
						faults.append("%s: a ring of %d points cannot be filled" % [code, ring.size()])
						continue
					rings.append(ring)
			_regions[code] = {"name": str(said.get("name", code)), "rings": rings}
		elif kind == "LineString" or kind == "MultiLineString":
			for line in ([coordinates] if kind == "LineString" else coordinates):
				var points := _points(line)
				if points.size() >= 2:
					_lines.append({"a": str(said.get("a", "")), "b": str(said.get("b", "")), "points": points})
	for code in _regions:
		for ring in _regions[code]["rings"]:
			for p in ring:
				low = low.min(p)
				high = high.max(p)
	if _regions.is_empty():
		error = "%s has no polygon with a code" % path.get_file()
		return error
	_bounds = Rect2(low, high - low)
	queue_redraw()
	return ""


## A list of [x, y] as points, north turned to the top of the screen.
static func _points(list: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if list is Array:
		for pair in list:
			if pair is Array and (pair as Array).size() >= 2:
				out.append(Vector2(float(pair[0]), -float(pair[1])))
	return out


## The codes of the map's regions, and a region's name.
func codes() -> PackedStringArray:
	return PackedStringArray(_regions.keys())


func region_name(code: String) -> String:
	return str(_regions.get(code, {}).get("name", ""))


## The place a region belongs to (its index in `places`), or -1.
func place_of(code: String) -> int:
	for i in places.size():
		if code in (places[i].get("regions", []) as Array):
			return i
	return -1


## The place at a point of the control, or -1 off the land.
func place_at(at: Vector2) -> int:
	_lay_out()
	for code in _rings:
		for ring in _rings[code]:
			if Geometry2D.is_point_in_polygon(at, ring):
				return place_of(code)
	return -1


## A point well inside a place, on the control: the middle of the box round its largest piece
## if that is on the piece, else one of the piece's own points. For the checks.
func point_in(index: int) -> Vector2:
	_lay_out()
	var best := PackedVector2Array()
	var most := 0.0
	for code in places[index].get("regions", []):
		for ring in _rings.get(str(code), []):
			var area := _box(ring).get_area()
			if area > most:
				most = area
				best = ring
	if best.is_empty():
		return Vector2(-1, -1)
	var middle := _box(best).get_center()
	if Geometry2D.is_point_in_polygon(middle, best):
		return middle
	var triangles := Geometry2D.triangulate_polygon(best)
	if triangles.size() >= 3:
		return (best[triangles[0]] + best[triangles[1]] + best[triangles[2]]) / 3.0
	return best[0]


static func _box(ring: PackedVector2Array) -> Rect2:
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	return box


## Where the land is drawn on the control.
func land() -> Rect2:
	_lay_out()
	return _land


func _lay_out() -> void:
	if _laid_for == size or _regions.is_empty():
		return
	_laid_for = size
	var room := Vector2(maxf(size.x - 8.0, 16.0), maxf(size.y - KEY_HEIGHT - 8.0, 16.0))
	var scale := minf(room.x / maxf(_bounds.size.x, 1.0), room.y / maxf(_bounds.size.y, 1.0))
	var drawn := _bounds.size * scale
	# The land stands at the top of its room, the key close beneath it.
	var origin := Vector2(floorf((size.x - 5.0 - drawn.x) * 0.5), 2.0)
	_land = Rect2(origin, drawn)
	_rings.clear()
	for code in _regions:
		var made := []
		for ring in _regions[code]["rings"]:
			made.append(_placed(ring, origin, scale))
		_rings[code] = made
	_paths.clear()
	for line in _lines:
		_paths.append({"a": line["a"], "b": line["b"], "points": _placed(line["points"], origin, scale)})


func _placed(points: PackedVector2Array, origin: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = origin + (points[i] - _bounds.position) * scale
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := place_at((event as InputEventMouseMotion).position)
		if at != chosen:
			chosen = at
			place_entered.emit(at)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := place_at((event as InputEventMouseButton).position)
		if at >= 0:
			place_pressed.emit(at)
			accept_event()


## The line beneath the key names the place under the pointer and its figure; only a place
## with no figure needs more said (why it has none).
func _get_tooltip(at: Vector2) -> String:
	var i := place_at(at)
	return str(places[i].get("note", "")) if i >= 0 and bool(places[i].get("silent", false)) else ""


func _draw() -> void:
	if _regions.is_empty():
		return
	_lay_out()
	# The land's hard shadow, then the land: each region in its place's tint.
	draw_set_transform(Vector2(3, 3))
	for code in _rings:
		for ring in _rings[code]:
			draw_colored_polygon(ring, Palette.SHADOW)
	draw_set_transform(Vector2.ZERO)
	for code in _rings:
		var index := place_of(code)
		var place: Dictionary = places[index] if index >= 0 else {}
		var silent := bool(place.get("silent", false))
		var tint := Palette.CARD_DEEP
		if index >= 0 and not silent and place.get("value") != null:
			tint = band_colour(band_of(float(place["value"])))
		elif silent:
			tint = Palette.CARD
		for ring in _rings[code]:
			draw_colored_polygon(ring, tint)
			if silent:
				_hatch(ring)
	# The lines: between two places a fine one, round the coast a firmer one; none between
	# two regions of one place.
	for path in _paths:
		var a := place_of(str(path["a"]))
		var b := place_of(str(path["b"])) if str(path["b"]) != "" else -2
		if b == -2:
			draw_polyline(path["points"], Palette.INK, 1.5, true)
		elif a != b:
			draw_polyline(path["points"], Palette.INK, 1.0, true)
	# The place marked out: its own edge, heavier.
	if chosen >= 0 and chosen < places.size():
		for path in _paths:
			var a := place_of(str(path["a"])) == chosen
			var b := str(path["b"]) != "" and place_of(str(path["b"])) == chosen
			if a != b:
				draw_polyline(path["points"], Palette.INK, 3.0, true)
	_draw_key()


## Slanting lines across a ring: a place with no figure.
func _hatch(ring: PackedVector2Array) -> void:
	var box := _box(ring)
	var reach := box.size.y
	var x := box.position.x - reach
	while x < box.end.x:
		var stroke := PackedVector2Array([Vector2(x, box.end.y), Vector2(x + reach, box.position.y)])
		for piece in Geometry2D.intersect_polyline_with_polygon(stroke, ring):
			if piece.size() >= 2:
				draw_line(piece[0], piece[-1], Palette.MUTED, 1.0, true)
		x += 5.0


## The key beneath the land: the bands, light to dark, with the figure at each edge; a hatched
## box where a place has no figure; and the place marked out, in words.
func _draw_key() -> void:
	var body := Palette.text(500)
	var strong := Palette.text(600)
	var top := _land.end.y + 14.0
	var box := Vector2(26, 10)
	var x := 2.0
	for i in BANDS.size():
		var at := Rect2(Vector2(x + i * (box.x + 2.0), top), box)
		draw_rect(at, band_colour(i))
		draw_rect(at, Palette.INK, false, 1.0)
	var marks := BANDS.duplicate()
	marks.append(TOP)
	for i in marks.size():
		var words := "%d" % int(roundf(float(marks[i]) * 100.0)) + ("%" if i == marks.size() - 1 else "")
		var centre := x + i * (box.x + 2.0) - 1.0
		draw_string(body, Vector2(centre - 20.0, top + box.y + 15.0), words, HORIZONTAL_ALIGNMENT_CENTER, 40.0, Palette.CAPS, Palette.MUTED)
	var silent := false
	for place in places:
		silent = silent or bool(place.get("silent", false))
	if silent:
		var at := Rect2(Vector2(x + BANDS.size() * (box.x + 2.0) + 34.0, top), Vector2(box.y + 4.0, box.y))
		draw_rect(at, Palette.CARD)
		_hatch(PackedVector2Array([at.position, Vector2(at.end.x, at.position.y), at.end, Vector2(at.position.x, at.end.y)]))
		draw_rect(at, Palette.INK, false, 1.0)
		draw_string(body, Vector2(at.position.x - 13.0, top + box.y + 15.0), "none", HORIZONTAL_ALIGNMENT_CENTER, 40.0, Palette.CAPS, Palette.MUTED)
	var line := measure
	var ink := Palette.MUTED
	if chosen >= 0 and chosen < places.size():
		var place: Dictionary = places[chosen]
		line = str(place.get("label", ""))
		if not bool(place.get("silent", false)) and place.get("value") != null:
			line += "  " + Format.percent(float(place["value"]))
		ink = Palette.INK
		if bool(place.get("silent", false)):
			line += "  none"
	draw_string(strong if ink == Palette.INK else body, Vector2(x, top + KEY_HEIGHT - 8.0), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, Palette.SMALL, ink)
