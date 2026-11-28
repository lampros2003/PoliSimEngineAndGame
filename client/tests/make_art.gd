extends SceneTree
## Stage S18.2: makes the game's own icon and opening picture from the plate that heads its
## sheets (scripts/plate.gd), so they are in the house style and from the same open pictograms:
##   client/icon.png    256 x 256: the seat of government in a roundel on a field of blue rays;
##   client/splash.png  the same over the game's name, shown on paper while the game loads.
## Needs a display (on a server, under xvfb-run); run it again after changing the plate, and
## commit what it writes:
##   godot --rendering-driver opengl3 --path client --script res://tests/make_art.gd

const Palette := preload("res://scripts/palette.gd")
const Plate := preload("res://scripts/plate.gd")


func _initialize() -> void:
	await _render(Vector2i(256, 256), func(canvas: Control) -> void:
		Plate.paint(canvas, Rect2(8, 8, 235, 235), "parliament", Palette.BLUE, PackedStringArray(), 24), "res://icon.png")
	await _render(Vector2i(560, 330), func(canvas: Control) -> void:
		Plate.paint(canvas, Rect2(170, 10, 215, 215), "parliament", Palette.BLUE, PackedStringArray(), 24)
		var face := Palette.display(500)
		var words := "PoliSim"
		var wide := face.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		canvas.draw_string(face, Vector2((560.0 - wide) / 2.0, 308.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Palette.INK), "res://splash.png")
	print("art: wrote client/icon.png and client/splash.png")
	quit(0)


## Draws on a clear ground of `size` pixels and saves the picture to `path`.
func _render(size: Vector2i, draw: Callable, path: String) -> void:
	var view := SubViewport.new()
	view.size = size
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var canvas := Control.new()
	canvas.size = Vector2(size)
	canvas.draw.connect(func() -> void: draw.call(canvas))
	view.add_child(canvas)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	view.queue_free()
