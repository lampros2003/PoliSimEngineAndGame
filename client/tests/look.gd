extends SceneTree
## Opens the scenario given by --scenario (without one, the start screen), plays --months
## months (answering any question put to the player with its first answer, so a run is
## never held up), then shows one state of the screen and saves a screenshot to
## --shot=FILE: --node=KEY opens a board node's popup ("policy:income_tax",
## "indicator:gdp", "centre"), --entry=NAME any value's popup, --overlay=budget|parliament
## a sheet, --hover=KEY points at a node, --type=lever:value types a change into a policy
## popup first (and --then=N plays N more months), --dilemma=1 leaves the question on screen, --effects=1 waits for the measured
## effects table first (for hover links). For a person to look at; needs a
## display. Godot's --resolution WxH before --path sets the window size.

var main: Control


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	var months := int(args.get("months", "0"))
	while main.started and main.game.steps_done() < months:
		var before: int = main.game.steps_done()
		if not main.unanswered_dilemmas().is_empty():
			if args.has("dilemma"):
				break
			for d in main.unanswered_dilemmas():
				main.answer_dilemma(str(d["name"]), 1)
			await _settle()
		main.advance(months - before)
		await _settle()
		if main.game.steps_done() == before and main.unanswered_dilemmas().is_empty():
			break
	if args.has("dilemma"):
		main.ask_dilemma()
	elif main.started and main._dialog != null and is_instance_valid(main._dialog):
		main._dialog.close()
	if args.has("effects"):
		for i in 2400:
			if not main.board.effects.is_empty() and not main.effects_running:
				break
			await process_frame
	if args.has("type"):
		var parts: PackedStringArray = str(args["type"]).split(":")
		main.type_lever(parts[0], float(parts[1]))
		await _settle()
		if not args.has("node"):
			main.close_popup()
		if args.has("then"):
			main.advance(int(args["then"]))
			await _settle()
	if args.has("overlay"):
		main.open_overlay(str(args["overlay"]))
	if args.has("node"):
		main.open_node(str(args["node"]))
	if args.has("entry"):
		main.open_indicator(str(args["entry"]))
	if args.has("hover"):
		main.hover(str(args["hover"]))
	await _settle()
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(str(args.get("shot", "user://look.png")))
	print("saved ", args.get("shot", "user://look.png"))
	while main.started and main.effects_running:  # let the table's thread finish before quitting
		await process_frame
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame
