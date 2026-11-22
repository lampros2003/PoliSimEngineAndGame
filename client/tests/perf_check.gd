extends SceneTree
## Stage S14.1: the speed budget (docs/S14-PLAN.md, "Speed"), measured through the interface
## on models/uk/scenarios/2025.toml with the screen at 1920x1080: a click to a popup fully
## open (120 ms), a popup closed (80 ms), "Next month" to the board showing the new month
## (150 ms), twelve months (1 s), pointing at a node to its links (the same frame), and an
## idle second with a popup open (nothing on the board redrawn). Prints every number, then
## fails if one is over its budget. Stage S14.4: months are timed while the effects table
## runs (they never wait for it); pointing at a policy straight after a month shows measured
## links from the table held; a forecast after a control moves, to "In a year" filled, within
## 600 ms: the engine's own ~300 ms for a 12-month look ahead, up to ~450 ms here when the
## effects table (restarted by the lever change, on every core but one) runs beside it, the
## 50 ms pause before it is asked, and a few frames. The plan's 250 ms is below the engine's own.
## Stage S15.1: a key typed into search (its matches, the list, the board dimmed) within 4 ms,
## with no engine call.
##
## Stage S17: the budgets are for the machine they were set on, and what they hold to account
## is the client; a slower machine is not a slower client (a shared Windows runner took
## 706 ms over a forecast that takes 323 ms here, with every other figure up as much, and
## the check failed on the same commit that passed beside it). So the machine is timed first,
## on work the client has no hand in: the engine's own twelve-month look ahead (both branches,
## on a game of its own, before the screen exists) and a fixed loop of script. Where the
## slower of the two takes k times its reference, the budgets for work the processor bounds
## (SCALED) are k times as long; on a machine as fast as the reference they stand as
## written. Opening and closing a popup are timed animations and an idle redraw is a count:
## those never stretch. A forecast over its budget is measured once more, as a popup is.

const BUDGET := {"open": 120.0, "close": 80.0, "month": 150.0, "year": 1000.0, "hover": 16.0, "idle_redraws": 0.0, "forecast": 600.0, "keystroke": 4.0}
## What the reference machine (four cores, where the budgets were set) takes over the two
## yardsticks, in milliseconds, best of three; and the budgets that stretch with them.
const REFERENCE := {"look_ahead": 255.0, "script": 85.0}
const SCALED := ["month", "year", "hover", "forecast", "keystroke"]

var main: Control
var _draws := {}


func _initialize() -> void:
	var machine := _machine()
	var slower: float = maxf(1.0, maxf(machine["look_ahead"] / REFERENCE["look_ahead"], machine["script"] / REFERENCE["script"]))
	var budget := {}
	for k in BUDGET:
		budget[k] = BUDGET[k] * (slower if k in SCALED else 1.0)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1920, 1080)
	await _settle()
	main.advance(1)
	await _settle()
	var board = main.board
	for layer in board.get_children():
		if layer is Control:
			var name := str(layer.name)
			_draws[name] = 0
			layer.draw.connect(func() -> void: _draws[name] += 1)
	var got := {}
	# A popup, opened and closed five times over a policy, an indicator and a group; once more
	# if over budget (the machine is shared: another program's burst is not the screen's).
	var timed: Array = await _popups()
	if timed[0] > budget["open"] or timed[1] > budget["close"]:
		var again: Array = await _popups()
		timed = [minf(timed[0], again[0]), minf(timed[1], again[1]), minf(timed[2], again[2])]
	got["open"] = timed[0]
	got["close"] = timed[1]
	var build_ms: float = timed[2]
	# Nothing on the board redrawn while a popup stands open and nothing happens.
	main.open_node("policy:income_tax")
	while not _open_done():
		await process_frame
	await _frames(20)
	await _quiet()
	for k in _draws:
		_draws[k] = 0
	var idle_from := Time.get_ticks_msec()
	while Time.get_ticks_msec() - idle_from < 1000:
		await process_frame
	var idle := 0
	for k in _draws:
		idle += int(_draws[k])
	got["idle_redraws"] = float(idle)
	var idle_detail := str(_draws)
	main.close_popup()
	await _settle()
	# Stage S15.1: a key typed into search: its matches, the list and the board's dimming, in
	# the same call (no engine call), averaged over a typed word and back.
	var typed := "unemployment"
	var keyed := Time.get_ticks_usec()
	for n in range(1, typed.length() + 1):
		main.search_for(typed.left(n))
	for n in range(typed.length() - 1, -1, -1):
		main.search_for(typed.left(n))
	got["keystroke"] = (Time.get_ticks_usec() - keyed) / 1000.0 / (2.0 * typed.length())
	main.search.clear_search()
	main.search.release_focus()
	await _frames(5)
	# A month, three times: from "Next month" to the date and board showing it, while the
	# table of the month before is still being measured.
	var months := []
	for i in 3:
		months.append(await _advance(1))
		await _frames(10)
	got["month"] = _median(months)
	got["year"] = await _advance(12)
	# Pointing at a policy straight after the year: measured links from the table held, in the
	# same call, while this month's table comes in.
	var began_hover := Time.get_ticks_usec()
	main.hover("policy:income_tax")
	var linked: bool = not board._links.is_empty() and board._links.all(func(l): return l["measured"])
	got["hover"] = (Time.get_ticks_usec() - began_hover) / 1000.0 if linked else 999.0
	var held: bool = main.effects_running
	main.hover("")
	await _frames(10)
	# A forecast after a control moves, three times; once more if over budget.
	await _settle()
	got["forecast"] = await _forecasts([21.0, 22.0, 21.5])
	if got["forecast"] > budget["forecast"]:
		got["forecast"] = minf(got["forecast"], await _forecasts([20.5, 22.5, 21.0]))
	main.game.cancel_lever("basic_rate")
	main.close_popup()
	await _settle()
	var words := PackedStringArray()
	var over := PackedStringArray()
	for k in BUDGET:
		words.append("%s %.1f (budget %.0f)" % [k, got[k], budget[k]])
		if got[k] > budget[k]:
			over.append(k)
	print("perf: %s; of opening, building the popup %.1f ms; hovered while the table was %s; idle redraws by layer %s; this machine %.2f times the reference's time (look ahead %.0f ms against %.0f, script %.0f ms against %.0f)" % [", ".join(words), build_ms,
		"still running" if held else "already in", idle_detail, slower, machine["look_ahead"], REFERENCE["look_ahead"], machine["script"], REFERENCE["script"]])
	while main.effects_running:
		await process_frame
	if not over.is_empty():
		push_error("over budget: " + ", ".join(over))
		quit(1)
		return
	quit(0)


## How fast this machine is, in milliseconds, each the best of three: `look_ahead`, the
## engine's own time for what a forecast asks of it (twelve months, as the game is and with a
## lever changed, on a game of its own with no screen and no effects table beside it), and
## `script`, a fixed loop of the kind of work the interface does (strings and dictionaries).
func _machine() -> Dictionary:
	var scenario := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.substr(11)
	var base := ProjectSettings.globalize_path("res://")
	for candidate in [base.path_join(scenario), base.path_join("..").path_join(scenario)]:
		if FileAccess.file_exists(candidate):
			scenario = candidate.simplify_path()
			break
	var look_ahead := 99999.0
	var probe := PoliSim.new()
	if probe.open(scenario) == "":
		probe.advance(1)
		while probe.is_busy():
			OS.delay_msec(1)
		probe.poll()
		var now: float = probe.latest("basic_rate")
		for value in [0.21, 0.22, 0.215]:
			probe.set_lever("basic_rate", value)  # both branches are new each time
			var asked := Time.get_ticks_usec()
			probe.request_forecast({"basic_rate": now}, 12, "speed")
			var answered := false
			while not answered and Time.get_ticks_usec() - asked < 20_000_000:
				OS.delay_msec(1)
				for event in probe.poll():
					answered = answered or str(event.get("kind", "")) == "forecast"
			if answered:
				look_ahead = minf(look_ahead, (Time.get_ticks_usec() - asked) / 1000.0)
	probe = null
	var script := 99999.0
	for n in 3:
		var began := Time.get_ticks_usec()
		var words := {}
		var total := 0
		for i in 200000:
			var key := "row%d" % (i % 997)
			words[key] = int(words.get(key, 0)) + i
			if key.contains("9"):
				total += key.length()
		script = minf(script, (Time.get_ticks_usec() - began) / 1000.0)
	return {"look_ahead": look_ahead, "script": script}


## The median, in milliseconds, of a forecast after the basic rate is typed at each of
## `values`: from the key to "In a year" filled for that setting.
func _forecasts(values: Array) -> float:
	var forecasts := []
	for value in values:
		var asked := Time.get_ticks_usec()
		main.type_lever("basic_rate", value)
		main.policy_card().year_shown = []  # the figures for this setting, not the last
		var took := 99999.0
		while Time.get_ticks_usec() - asked < 20_000_000:
			await process_frame
			var card = main.policy_card()
			if card != null and not card.measuring and not card.year_shown.is_empty():
				took = (Time.get_ticks_usec() - asked) / 1000.0
				break
		forecasts.append(took)
		await _frames(5)
	return _median(forecasts)


## [open, close, of opening the build], medians of five, in milliseconds.
func _popups() -> Array:
	var opens := []
	var closes := []
	var builds := []
	for key in ["policy:income_tax", "indicator:gdp", "group:pensioner", "policy:vat", "indicator:unemployment_rate"]:
		var began := Time.get_ticks_usec()
		main.open_node(key)
		builds.append((Time.get_ticks_usec() - began) / 1000.0)
		while not _open_done():
			await process_frame
		opens.append((Time.get_ticks_usec() - began) / 1000.0)
		await _frames(10)
		began = Time.get_ticks_usec()
		main.close_popup()
		while main.popup.visible:
			await process_frame
		closes.append((Time.get_ticks_usec() - began) / 1000.0)
		await _frames(5)
	return [_median(opens), _median(closes), _median(builds)]


## True once the popup's card has grown to its full size and opacity.
func _open_done() -> bool:
	var card: Control = main.popup.card
	return main.popup.is_open() and card.scale.is_equal_approx(Vector2.ONE) and card.modulate.a >= 0.999 and card.size.x > 10.0


## Runs `count` months from the screen's button and returns the milliseconds until the date
## says the last of them and the board has been refreshed for it. A question put to the
## player stops a run: it is answered (untimed) and the run goes on.
func _advance(count: int) -> float:
	var target: int = main.game.steps_done() + count
	var spent := 0.0
	while main.game.steps_done() < target:
		for d in main.unanswered_dilemmas():
			main.answer_dilemma(str(d["name"]), 1)
		if main.dilemma_dialog != null and is_instance_valid(main.dilemma_dialog):
			main.dilemma_dialog.close()
		while main.game.is_busy() or not main.can_advance():
			await process_frame
		var began := Time.get_ticks_usec()
		var from: int = main.game.steps_done()
		main.advance(target - from)
		while true:
			await process_frame
			var done: int = main.game.steps_done()
			if not main.game.is_busy() and done > from and str(main._date.text).ends_with("%d/%d" % [done, main.term]):
				break
			if Time.get_ticks_usec() - began > 60_000_000:
				return 99999.0
		spent += (Time.get_ticks_usec() - began) / 1000.0
	return spent


## Waits until the effects table asked for after the last month is in: the budgets are for
## a screen at rest (the table's threads share the machine with the month).
func _quiet() -> void:
	while main.effects_running or main._effects_timer.time_left > 0.0:
		await process_frame
	await _frames(5)


func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 4:
		await process_frame
