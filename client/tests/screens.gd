extends SceneTree
## Plays a short scripted session through the real interface and saves screenshots to
## the folder given by --shots=DIR. Needs a display (on a server, run under xvfb-run).
## It uses Valmora's levers: run it with --scenario=models/valmora/scenarios/term.toml.

var main: Control
var shots := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	await _shot("01-start")
	main.advance(12)
	await _settle()
	main.levers.type_value("basic_rate", 23.0)
	main.levers.type_value("gov_purchases", 12500000000.0)
	await _settle()
	await _shot("02-pending")
	main.advance(12)
	await _settle()
	main.add_to_chart("gdp")
	main.add_to_chart("consumption_total")
	main.explain("gov_balance", true)
	await _settle()
	await _shot("03-chart-and-why")
	main.explain("income_tax_total", true)
	await _settle()
	main.explain("income_tax", true)
	await _settle()
	await _shot("04-follow")
	main.add_to_chart("unemployment_rate")
	main.advance(12)
	await _settle()
	main.advance(12)
	await _settle()
	main.advance(12)
	await _settle()
	await _shot("05-end-of-term")
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy():
		await process_frame
	for i in 4:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := shots.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
