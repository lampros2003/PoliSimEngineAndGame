extends Control
## Stage S18.3: a plate: the picture at the head of a question put to the player, of election
## night, of the end of a term and of the start screen, in the manner of a printed
## public-information poster: a field of one flat ink with rays behind a roundel of card
## stock, and in the roundel one large pictogram; smaller ones may stand either side of it.
## Nothing here is drawn for one event: a plate is made from a pictogram's name (the open
## set in client/icons) and a tone, so a scenario gives each of its questions a plate with
## one line (`[play.plates]`), and a mod's question has one without a line.

const Palette := preload("res://scripts/palette.gd")

const HEIGHT := 132.0
## The tones a plate may be printed in, by name.
const TONES := {"ochre": Palette.OCHRE, "blue": Palette.BLUE, "brick": Palette.BRICK, "sage": Palette.SAGE, "ink": Palette.INK}

## The pictogram in the roundel, and the smaller ones either side of it (none, or any number).
var icon := "government"
var beside: PackedStringArray = []
var tone: Color = Palette.OCHRE
## How many rays stand behind the roundel (every other one a shade deeper).
var rays := 28


## A plate from what a scenario says of it: a pictogram's name, or {icon, tone, beside}.
static func from(spec: Variant, fallback_icon := "government", fallback_tone := "ochre") -> Control:
	var plate: Control = load("res://scripts/plate.gd").new()
	var said: Dictionary = spec if spec is Dictionary else ({"icon": str(spec)} if spec != null and str(spec) != "" else {})
	plate.icon = str(said.get("icon", fallback_icon))
	plate.tone = TONES.get(str(said.get("tone", fallback_tone)), Palette.OCHRE)
	plate.beside = PackedStringArray(said.get("beside", []))
	return plate


func _init() -> void:
	name = "plate"
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size - Vector2(5, 5)), icon, tone, beside, rays)


## Paints a plate on `canvas` in `rect` (its hard shadow falls 5 px below and to the right of
## it): used by the control above, and to make the game's own icon and opening picture.
static func paint(canvas: CanvasItem, rect: Rect2, picture: String, ink: Color, others: PackedStringArray = [], ray_count := 28) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	canvas.draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size), Palette.SHADOW)
	canvas.draw_rect(rect, ink)
	# Rays from the roundel's centre, every other one a shade deeper, cut to the plate.
	var centre := rect.get_center()
	var reach := rect.size.length()
	var deeper := ink.darkened(0.14) if ink != Palette.INK else ink.lightened(0.12)
	var frame := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for k in range(0, ray_count, 2):
		var a := TAU * (k - 0.5) / ray_count
		var b := TAU * (k + 0.5) / ray_count
		var ray := PackedVector2Array([centre, centre + Vector2(cos(a), sin(a)) * reach, centre + Vector2(cos(b), sin(b)) * reach])
		for piece in Geometry2D.intersect_polygons(ray, frame):
			canvas.draw_colored_polygon(piece, deeper)
	# The smaller pictograms, in card stock on the field, either side of the roundel.
	var r := minf(rect.size.y * 0.41, rect.size.x * 0.3)
	var small := int(roundf(r * 0.8))
	var places := others.size()
	for i in places:
		var side := -1.0 if i % 2 == 0 else 1.0
		var step := float(i / 2 + 1)
		var x := centre.x + side * (r + 16.0 + (small + 24.0) * (step - 0.5))
		if x - small * 0.5 < rect.position.x + 8.0 or x + small * 0.5 > rect.end.x - 8.0:
			continue
		var at := (Vector2(x, centre.y) - Vector2(small, small) * 0.5).round()
		canvas.draw_texture_rect(Palette.icon(others[i], small), Rect2(at, Vector2(small, small)), false, Color(Palette.CARD, 0.92))
	# The roundel: card stock with an ink edge and a hard shadow, a hairline inside the edge.
	canvas.draw_circle(centre + Vector2(4, 4), r, Palette.SHADOW, true, -1.0, true)
	canvas.draw_circle(centre, r, Palette.CARD, true, -1.0, true)
	canvas.draw_arc(centre, r, 0, TAU, 96, Palette.INK, 3.0, true)
	canvas.draw_arc(centre, r - 6.0, 0, TAU, 96, Palette.INK, 1.0, true)
	var px := int(roundf(r * 1.18))
	canvas.draw_texture_rect(Palette.icon(picture, px), Rect2((centre - Vector2(px, px) * 0.5).round(), Vector2(px, px)), false, Palette.INK)
	canvas.draw_rect(rect, Palette.INK, false, 2.0)
