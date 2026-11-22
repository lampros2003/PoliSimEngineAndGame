extends Control
## A time-series chart drawn by hand: one or two figures sharing one unit, policy changes
## marked on the time axis, values shown under the pointer. Click a legend entry to
## remove that figure. Stage S13.2: drawn straight onto the popup's card stock.

const Palette := preload("res://scripts/palette.gd")

signal series_removed(row: String)

var fmt: RefCounted  # format.gd
var entry := {}  # catalogue entry that sets the unit of the axis
var series: Array = []  # {row, label, values: PackedFloat64Array (already scaled for display), color}
var steps := PackedInt64Array()
var markers: Array = []  # {step, text}
var hover := -1
var _legend_boxes: Array = []  # [Rect2, row]

const PAD_LEFT := 96.0
## Stage S17.1: the room the value labels have, PAD_LEFT or what the widest of them needs
## ("54.00p a litre" was cut short).
var _pad_left := PAD_LEFT
const PAD_RIGHT := 18.0
const PAD_TOP := 40.0
const PAD_BOTTOM := 34.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Stage S14.1: the size its popup gives it, or this.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(320, 220)


func set_data(new_steps: PackedInt64Array, new_markers: Array) -> void:
	steps = new_steps
	markers = new_markers
	queue_redraw()


func has_row(row: String) -> bool:
	for s in series:
		if s["row"] == row:
			return true
	return false


func _plot_rect() -> Rect2:
	# Stage S14.1: one line needs no legend (the popup's title names it), so no room for one.
	var top := PAD_TOP if series.size() > 1 else 14.0
	return Rect2(_pad_left, top, maxf(10.0, size.x - _pad_left - PAD_RIGHT), maxf(10.0, size.y - top - PAD_BOTTOM))


func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s in series:
		for v in s["values"]:
			if is_finite(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)
	if lo == INF:
		return Vector2(0, 1)
	if lo == hi:
		var pad := absf(lo) * 0.05 if lo != 0.0 else 1.0  # a flat line, a little room round it
		return Vector2(lo - pad, hi + pad)
	var span := hi - lo
	var ticks := _nice_ticks(lo - span * 0.08, hi + span * 0.08)
	if ticks.size() < 2:
		return Vector2(lo - span * 0.08, hi + span * 0.08)
	# Stage S16.1: out to the gridlines either side of the data, so every line sits between two
	# labelled values.
	var step := ticks[1] - ticks[0]
	return Vector2(floorf(lo / step) * step, ceilf(hi / step) * step)


static func _nice_ticks(lo: float, hi: float, wanted := 5) -> PackedFloat64Array:
	var span := hi - lo
	var raw := span / float(wanted)
	var power := pow(10.0, floorf(log(raw) / log(10.0)))
	var step := power
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if power * m >= raw:
			step = power * m
			break
	var ticks := PackedFloat64Array()
	var t := ceilf(lo / step) * step
	while t <= hi + step * 1e-9:
		ticks.append(t)
		t += step
	return ticks


func _x(i: int, rect: Rect2) -> float:
	if steps.size() <= 1:
		return rect.position.x + rect.size.x * 0.5
	return rect.position.x + rect.size.x * float(i) / float(steps.size() - 1)


func _y(v: float, rect: Rect2, r: Vector2) -> float:
	return rect.end.y - rect.size.y * (v - r.x) / (r.y - r.x)


## A rate to two places, always two (a trailing nought kept, so a scale's marks line up).
func _percent2(v: float) -> String:
	var words: String = fmt.percent(v, 2)
	var body := words.trim_suffix("%")
	var places := body.length() - body.find(".") - 1 if body.contains(".") else 0
	if places == 0:
		body += "."
	return body + "0".repeat(maxi(0, 2 - places)) + "%"


func _label(v: float) -> String:
	if fmt == null:
		return str(v)
	return fmt.value(entry, int(v) if entry.get("type", "") == "int" else v, true, false, true)


func _draw() -> void:
	var font := get_theme_default_font()
	var small := Palette.SMALL
	_pad_left = PAD_LEFT
	var rect := _plot_rect()
	_legend_boxes.clear()
	if series.is_empty():
		draw_string(font, Vector2(PAD_LEFT, size.y * 0.5), "Its history appears after the first month.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE, Palette.MUTED)
		return
	var r := _range()
	# Grid and value labels.
	var ticks := _nice_ticks(r.x, r.y)
	# A rate whose gridlines are closer than a tenth of a point is marked to two places, so
	# they do not all read the same (a gilt yield moving by hundredths).
	# Stage S17.1: also when they are not whole tenths of a point (20.25% and 20.75% read 20.2%
	# and 20.8%), and every mark to the same number of places (4.34%, 4.32%, 4.30%).
	var gap: float = (ticks[1] - ticks[0]) * 100.0 if ticks.size() > 1 else 1.0
	var fine: bool = fmt != null and fmt.is_rate(entry) and ticks.size() > 1 and (gap < 0.099 or not is_equal_approx(gap * 10.0, roundf(gap * 10.0)))
	# Stage S17.1: the gridlines at both ends of the range are drawn and marked, so no line runs
	# outside the marked values (the ends are whole steps: see _range).
	if ticks.size() > 1:
		var step: float = ticks[1] - ticks[0]
		if ticks[0] - r.x > step * 0.5 and is_equal_approx(roundf(r.x / step), r.x / step):
			ticks.insert(0, r.x)
		if r.y - ticks[-1] > step * 0.5 and is_equal_approx(roundf(r.y / step), r.y / step):
			ticks.append(r.y)
	var marks := {}
	var last_words := ""
	for t in ticks:
		var words: String = _percent2(t) if fine else _label(t)
		# Stage S17.1: a mark that reads as the one below it is left off (£2.91tn twice).
		marks[t] = "" if words == last_words else words
		last_words = words
		_pad_left = maxf(_pad_left, font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 16.0)
	rect = _plot_rect()
	for t in ticks:
		# Stage S13.5: a whole-number value (an age, a year, a level) is marked at whole numbers only.
		if ((entry.get("type", "") == "int" and not entry.get("money", false)) or entry.has("levels")) and not is_equal_approx(t, roundf(t)):
			continue
		var y := _y(t, rect, r)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Palette.RULE, 1.0)
		if str(marks[t]) != "":
			draw_string(font, Vector2(4, y + 5), str(marks[t]), HORIZONTAL_ALIGNMENT_RIGHT, _pad_left - 12, small, Palette.MUTED)
	if r.x < 0.0 and r.y > 0.0:
		var zero := _y(0.0, rect, r)
		draw_line(Vector2(rect.position.x, zero), Vector2(rect.end.x, zero), Palette.MUTED, 1.0)
	# Time axis: a label at the start of each year, or every quarter when short.
	var every := 12 if steps.size() > 30 else 3
	for i in steps.size():
		var step := int(steps[i])
		if fmt != null and (fmt.start_month + step) % every == 0:
			var x := _x(i, rect)
			draw_line(Vector2(x, rect.end.y), Vector2(x, rect.end.y + 4), Palette.MUTED, 1.0)
			draw_string(font, Vector2(x - 40, rect.end.y + 20), fmt.month_name(step, true), HORIZONTAL_ALIGNMENT_CENTER, 80, small, Palette.MUTED)
	# Policy changes.
	for m in markers:
		var index := steps.find(int(m["step"]))
		if index < 0:
			continue
		var x := _x(index, rect)
		draw_dashed_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Palette.PENDING.darkened(0.2), 1.0, 4.0)
	# Lines.
	for s in series:
		var points := PackedVector2Array()
		var values: PackedFloat64Array = s["values"]
		for i in mini(values.size(), steps.size()):
			if is_finite(values[i]):
				points.append(Vector2(_x(i, rect), _y(values[i], rect, r)))
			elif points.size() > 0:
				_polyline(points, s["color"])
				points = PackedVector2Array()
		_polyline(points, s["color"])
	# Legend, for two lines.
	var x := _pad_left
	for s in (series if series.size() > 1 else []):
		var text: String = s["label"] + ("  ×" if series.size() > 1 and s != series[0] and s.get("removable", true) else "")
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_rect(Rect2(x, 14, 12, 12), s["color"])
		draw_string(font, Vector2(x + 18, 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Palette.TEXT)
		_legend_boxes.append([Rect2(x, 8, width + 22, 24), s["row"]])
		x += width + 40
	# Hover read-out.
	if hover >= 0 and hover < steps.size():
		var hx := _x(hover, rect)
		draw_line(Vector2(hx, rect.position.y), Vector2(hx, rect.end.y), Palette.MUTED, 1.0)
		var lines := PackedStringArray([fmt.month_name(int(steps[hover])) if fmt else str(steps[hover])])
		for s in series:
			var values: PackedFloat64Array = s["values"]
			if hover < values.size() and is_finite(values[hover]):
				lines.append("%s: %s" % [s["label"], _label(values[hover])])
				draw_circle(Vector2(hx, _y(values[hover], rect, r)), 3.5, s["color"])
		for m in markers:
			if int(m["step"]) == int(steps[hover]):
				lines.append(m["text"])
		var box_w := 0.0
		for line in lines:
			box_w = maxf(box_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x)
		var box := Rect2(hx + 10, rect.position.y + 6, box_w + 16, 20 * lines.size() + 8)
		if box.end.x > size.x - 4:
			box.position.x = hx - box.size.x - 10
		draw_style_box(Palette.card(0, 3, 1), box)
		for i in lines.size():
			draw_string(font, box.position + Vector2(8, 20 + 20 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, small, Palette.TEXT)


func _polyline(points: PackedVector2Array, color: Color) -> void:
	if points.size() >= 2:
		draw_polyline(points, color, 2.5, true)
	elif points.size() == 1:
		draw_circle(points[0], 4.0, color)  # a first month's one point: a mark that can be seen


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var rect := _plot_rect()
		var previous := hover
		hover = -1
		if steps.size() > 0 and rect.grow(8).has_point(event.position):
			var t := clampf((event.position.x - rect.position.x) / rect.size.x, 0.0, 1.0)
			hover = int(roundf(t * float(steps.size() - 1)))
		if hover != previous:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for box in _legend_boxes:
			if box[0].has_point(event.position):
				series_removed.emit(box[1])
				return


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
		hover = -1
		queue_redraw()
