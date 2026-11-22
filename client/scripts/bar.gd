extends Control
## A bar that grows right from the centre for a positive share and left for a negative one.

const Palette := preload("res://scripts/palette.gd")

var fraction := 0.0  # -1 to 1
## Stage S13.2: the colours of a rise and a fall (good and bad unless set otherwise).
var up_colour := Palette.GOOD
var down_colour := Palette.BAD


func _ready() -> void:
	custom_minimum_size = Vector2(160, 18)


func _draw() -> void:
	var mid := size.x * 0.5
	draw_line(Vector2(mid, 0), Vector2(mid, size.y), Palette.INK, 1.5)
	var width := clampf(absf(fraction), 0.0, 1.0) * (mid - 2.0)
	if width < 1.0:
		return
	var color := up_colour if fraction > 0.0 else down_colour
	var x := mid if fraction > 0.0 else mid - width
	draw_rect(Rect2(x, 3, width, size.y - 6), color)
