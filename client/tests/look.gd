extends SceneTree
## Opens the scenario given by --scenario (without one, the start screen), plays --months
## months (answering any question put to the player with its first answer, so a run is
## never held up), then shows one state of the screen and saves a screenshot to
## --shot=FILE: --node=KEY opens a board node's popup ("policy:income_tax",
## "indicator:gdp", "centre"), --entry=NAME any value's popup, --overlay=budget|parliament
## a sheet, --hover=KEY points at a node, --type=lever:value types a change into a policy
## popup first (and --then=N plays N more months), --dilemma=1 leaves the question on screen, --effects=1 waits for the measured
## effects table first (for hover links). Stage S13.4: --node=group:KEY opens a group's
## popup, and --household=N then opens its Nth household's account. Stage S13.6: --report=1
## shows the month's report, --guide=N the guide's Nth step. Stage S14.1: --key=1 the key.
## Stage S15.1: --add=1|KEY the Add policy sheet, --search=WORDS (+ for a space) the search,
## --situation=NAME a situation lit on its node. Stage S13.5: --introduce and
## --draft (below). For a person to look at; needs a
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
	# Stage S13.5: --introduce=KEY:VALUE[,KEY:VALUE] introduces policies not in force (and
	# --then=N plays on); --draft=KEY:VALUE opens one to be introduced with that setting picked.
	if args.has("introduce"):
		for item in str(args["introduce"]).split(","):
			main.introduce_policy(item.get_slice(":", 0) + ":" + item.get_slice(":", 1), float(item.get_slice(":", 2)))
			await _settle()
		if args.has("then"):
			main.advance(int(args["then"]))
			await _settle()
	if args.has("draft"):
		var item := str(args["draft"])
		main.open_node(item.get_slice(":", 0) + ":" + item.get_slice(":", 1))
		await _settle()
		main.policy_card().type_value(main.policy_card().levers[0], float(item.get_slice(":", 2)))
		var until := Time.get_ticks_msec() + 30000
		while main.policy_card().year_shown.is_empty() and Time.get_ticks_msec() < until:
			await process_frame
	# The pointer of whoever runs this must not point at the board for the picture.
	main.board.input_enabled = false
	main.board.set_hover("")
	if args.has("overlay"):
		main.open_overlay(str(args["overlay"]))
	if args.has("node"):
		main.open_node(str(args["node"]))
	if args.has("household"):
		for i in 1200:
			if main.group_card() != null and not main.group_card().records.is_empty():
				break
			await process_frame
		await _settle()
		main.group_card().household_opened.emit(main.group_card().records[int(args["household"])])
	if args.has("entry"):
		main.open_indicator(str(args["entry"]))
	if args.has("hover"):
		main.hover(str(args["hover"]))
	# Stage S13.6: --report=1 shows the last month's report, --guide=N the guide's Nth step.
	if args.has("report"):
		main.report.reopen()
	# Stage S15.1: --add=1 (or --add=KEY) the Add policy sheet; --search=WORDS the search
	# with its results; --situation=NAME a situation's popup on its lit node.
	if args.has("add"):
		if str(args["add"]).begins_with("area:"):
			main.open_introduce(str(args["add"]).trim_prefix("area:").replace("+", " "))
		else:
			main.open_add_policy("" if str(args["add"]) == "1" else str(args["add"]))
	if args.has("search"):
		main.search_for(str(args["search"]).replace("+", " "))
		if args.has("pick"):  # stage S15.5: --pick=N opens the Nth match (from 0)
			main._open_result(main.search.found[int(args["pick"])])
	if args.has("situation"):
		main.open_situation(str(args["situation"]))
	# Stage S16.1: --menu=1 opens the menu; --notice=1 shows a problem notice.
	if args.has("menu"):
		main._menu.show_popup()
	if args.has("notice"):
		main._show_message("[b]Could not load[/b]: the save file is from a newer version of the game.", true)
	# Stage S14.1: --key=1 shows the key.
	if args.has("key"):
		main.show_key()
	if args.has("guide"):
		main.show_guide(false)
		for i in int(args["guide"]) - 1:
			main.guide.next()
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
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 4:
		await process_frame
