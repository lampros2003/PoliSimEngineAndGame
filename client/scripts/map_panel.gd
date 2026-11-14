extends PanelContainer
## Stage S12.6: the map. A tile cartogram of one dimension (the UK's twelve regions and
## nations), laid out by the scenario's [play.map] table, each tile coloured on one blue
## scale by the statistic chosen, from the lowest value (palest) to the highest (darkest),
## with its value written on it.
##
##   [play.map]
##   dim = "region"                       # the dimension the tiles stand for
##   statistics = ["net_income_by_region", "regional_unemployment"]
##   tiles = [[3, 1], [2, 2], ...]        # [column, row] per member, in the dimension's order

const Palette := preload("res://scripts/palette.gd")
const TILE := 88.0
const GAP := 6.0
const PALE := Color("#e3ebf3")

var fmt: RefCounted
var statistics: PackedStringArray = []
var tiles: Array = []
var _entries := {}
var _choice: OptionButton
var _canvas: Control
var _legend: Label
var _values := PackedFloat64Array()
var _labels := PackedStringArray()
var _cells_of: Callable


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Map"
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_choice = OptionButton.new()
	_choice.name = "map_statistic"
	_choice.item_selected.connect(func(_i: int) -> void: refresh(_cells_of))
	head.add_child(_choice)
	_legend = Label.new()
	_legend.add_theme_color_override("font_color", Palette.MUTED)
	_legend.add_theme_font_size_override("font_size", Palette.SMALL)
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_legend)
	_canvas = Control.new()
	_canvas.name = "map_canvas"
	_canvas.draw.connect(_draw_tiles)
	box.add_child(_canvas)


## The scenario's [play] table and the catalogue (name -> entry). False if there is no map.
func build(play: Dictionary, entries: Dictionary) -> bool:
	_entries = entries
	var map: Dictionary = play.get("map", {})
	statistics = PackedStringArray()
	for name in map.get("statistics", []):
		if entries.has(str(name)):
			statistics.append(str(name))
	tiles = map.get("tiles", [])
	var chosen := _choice.selected
	_choice.clear()
	for name in statistics:
		_choice.add_item(str(entries[name].get("label", name)))
	if statistics.size() > 0:
		_choice.select(clampi(chosen, 0, statistics.size() - 1))
	var columns := 0.0
	var rows := 0.0
	for t in tiles:
		columns = maxf(columns, float(t[0]) + 1.0)
		rows = maxf(rows, float(t[1]) + 1.0)
	_canvas.custom_minimum_size = Vector2(columns * (TILE + GAP), rows * (TILE + GAP))
	return not statistics.is_empty() and not tiles.is_empty()


## The statistic chosen, from the bridge's cells(); for tests.
func statistic() -> String:
	return statistics[_choice.selected] if _choice.selected >= 0 and _choice.selected < statistics.size() else ""


func refresh(cells_of: Callable) -> void:
	_cells_of = cells_of
	_values = PackedFloat64Array()
	_labels = PackedStringArray()
	if cells_of.is_valid() and statistic() != "":
		var data: Dictionary = cells_of.call(statistic())
		_values = data.get("values", PackedFloat64Array())
		_labels = data.get("labels", PackedStringArray())
	if _values.size() != tiles.size():
		_values = PackedFloat64Array()
	var entry: Dictionary = _entries.get(statistic(), {})
	if _values.is_empty():
		_legend.text = "Advance a month to see the map."
	else:
		var about := str(entry.get("doc", "")) if str(entry.get("doc", "")) != "" else str(entry.get("label", ""))
		_legend.text = "%s. Palest %s, darkest %s." % [about.rstrip("."),
			fmt.value(entry, _lowest(), true, false), fmt.value(entry, _highest(), true, false)]
	_canvas.queue_redraw()


func _lowest() -> float:
	return Array(_values).min() if not _values.is_empty() else 0.0


func _highest() -> float:
	return Array(_values).max() if not _values.is_empty() else 0.0


## A tile's colour: palest for the lowest value, the theme's navy for the highest.
func colour_of(value: float) -> Color:
	var span := _highest() - _lowest()
	var t := 0.5 if span <= 0.0 else (value - _lowest()) / span
	return PALE.lerp(Palette.ACCENT, t)


func _draw_tiles() -> void:
	if _values.is_empty():
		return
	var font := get_theme_default_font()
	var entry: Dictionary = _entries.get(statistic(), {})
	for i in tiles.size():
		var at := Vector2(float(tiles[i][0]), float(tiles[i][1])) * (TILE + GAP)
		var colour := colour_of(_values[i])
		_canvas.draw_rect(Rect2(at, Vector2(TILE, TILE)), colour)
		var ink := Color.WHITE if colour.get_luminance() < 0.5 else Palette.TEXT
		var label := _labels[i] if i < _labels.size() else ""
		_canvas.draw_multiline_string(font, at + Vector2(8, 20), label, HORIZONTAL_ALIGNMENT_LEFT, TILE - 14,
			Palette.SMALL - 1, 3, ink)
		_canvas.draw_string(font, at + Vector2(8, TILE - 12), fmt.value(entry, _values[i], true, false),
			HORIZONTAL_ALIGNMENT_LEFT, TILE - 14, Palette.SMALL + 1, ink)
