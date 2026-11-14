extends SceneTree
## Opens the scenario given by --scenario, plays --months months, charts the rows listed in
## --chart=a,b, explains --why=name and saves a screenshot to --shot=FILE. For looking at a
## model's screen; needs a display (xvfb-run on a server).

var main: Control


func _initialize() -> void:
	var shot := ""
	var months := 0
	var charted := PackedStringArray()
	var why := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
		elif arg.begins_with("--months="):
			months = int(arg.substr(9))
		elif arg.begins_with("--chart="):
			charted = arg.substr(8).split(",")
		elif arg.begins_with("--why="):
			why = arg.substr(6)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if months > 0:
		main.advance(months)
		await _settle()
	for row in charted:
		main.add_to_chart(row)
	if why != "":
		main.explain(why, true)
		await _settle()
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shot)
	print("saved ", shot)
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
