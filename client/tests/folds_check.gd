extends SceneTree
## Stage S17.1: every fold of every kind of popup, and every sheet, opened at 1366x768 and
## 1920x1080 through the real bridge (models/uk/scenarios/2025.toml), and held to what can be
## measured of stage S16's checklist: the card inside the window and under the top bar; nothing
## in it wider than it or poking out of its sides; no label narrower than its words; no text
## under 12 px; a scroll bar only where the content is taller than the room. With --shots=DIR
## (and a display: on a server, under xvfb-run) each state is also photographed, the card
## alone, for a person to read; --only=1366 or --only=1920 keeps to one size.
##
## The states: a policy in force with a change waiting and its year ahead, a policy of levels,
## a policy being introduced; a statistic with each of its folds, one with "who gains, who
## loses", one off the board; a group of voters counted from households with each fold and a
## household's account, an estimated group, a group of belief; a situation; The Budget,
## Parliament with each fold, Add policy, the key, help, a question put to the player and
## the month's report. Also: a popup opened in the moment another closes holds only its own
## content (the first one's stayed under it).
## Stage S19: and no explainer notes: no piece of muted text on any card is longer than
## LONGEST_NOTE characters, unless it is the model's own words (meta "content").

const Contrast := preload("res://scripts/contrast.gd")

const SIZES := [Vector2i(1366, 768), Vector2i(1920, 1080)]
const SMALLEST_TEXT := 12
## Stage S19: the longest a piece of muted text on a card may be, in characters.
const LONGEST_NOTE := 72

var main: Control
var shots := ""
var only := 0
var _faults := PackedStringArray()
var _notes := {}  # a note already reported -> the state it was first seen in
var _states := 0
var _view := Vector2i.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.substr(8)
		if arg.begins_with("--only="):
			only = int(arg.substr(7))
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.content_scale_factor = 1.0  # as the game starts in its own window
	await _settle()
	main.advance(1)
	await _settle()
	for d in main.unanswered_dilemmas():
		main.answer_dilemma(str(d["name"]), 1)
	await _settle()
	main.report.dismiss()
	# The effects table, for "what moves it most" and the policies that matter to a group.
	var until := Time.get_ticks_msec() + 180000
	while (main.effects_running or main.board.effects.is_empty()) and Time.get_ticks_msec() < until:
		await process_frame
	main.board.input_enabled = false
	for view in SIZES:
		if only != 0 and view.x != only:
			continue
		_view = view
		root.size = view
		root.content_scale_factor = 1.0
		await _frames(6)
		if Vector2i(root.get_visible_rect().size) != view:
			return _fail("the window is %s, not %s" % [root.get_visible_rect().size, view])
		await _popups()
		await _sheets()
	while main.effects_running:
		await process_frame
	if not _faults.is_empty():
		for line in _faults:
			push_error(line)
		print("folds: %d faults in %d states" % [_faults.size(), _states])
		quit(1)
		return
	print("folds: %d states at %s: every fold of a policy, a statistic, a group of voters and a situation, and every sheet, inside the window and under the top bar, nothing wider than its card, no label narrower than its words, no text under %d px%s" % [
		_states, " and ".join(SIZES.filter(func(s): return only == 0 or s.x == only).map(func(s): return "%dx%d" % [s.x, s.y])),
		SMALLEST_TEXT, "" if shots == "" else "; photographed to " + shots])
	quit(0)


# ---------------------------------------------------------------------------- the states

func _popups() -> void:
	await _screen("board")
	# Stage S18.1: the board's own pictograms, and the top bar's, at the size they are shown.
	main.board.icons_drawn.clear()
	main.board.queue_layers()
	await _frames(4)
	if main.board.icons_drawn.is_empty() and DisplayServer.get_name() != "headless":
		_faults.append("the board drew no pictogram at %dx%d" % [_view.x, _view.y])
	for line in Contrast.Palette.unsharp(main._bar):
		_faults.append("the top bar at %dx%d: %s" % [_view.x, _view.y, line])
	# A policy in force: at rest, then with a change waiting and the year ahead.
	main.open_node("policy:income_tax")
	await _open()
	await _state("policy-income_tax", main.popup.card)
	main.type_lever("basic_rate", 23.0)  # not 21: the walk's own bill, further on, makes it 21
	await _year()
	await _state("policy-income_tax-changed", main.popup.card)
	await _screen("board-with-popup")
	main.game.cancel_lever("basic_rate")
	main.close_popup()
	await _settle()
	# A policy of named levels; one that can be repealed.
	for key in ["policy:planning_rules", "policy:winter_fuel_payment", "policy:drinking_age", "policy:fuel_duty"]:
		main.open_node(key)
		await _open()
		await _state(key.replace(":", "-"), main.popup.card)
		main.close_popup()
		await _settle()
	# A popup closed and another opened in the same moment holds only the second.
	main.open_node("policy:income_tax")
	await _open()
	main.close_popup()
	main.open_node("indicator:gdp")
	await _open()
	if main.popup._holder.get_child_count() != 1 or main.indicator_card() == null:
		_faults.append("a popup opened as another closed holds %d contents" % main.popup._holder.get_child_count())
	main.close_popup()
	await _settle()
	# A policy being introduced, with its setting picked.
	main.open_node("policy:ev_grant")
	await _open()
	await _state("policy-ev_grant-introduce", main.popup.card)
	main.policy_card().type_value("ev_grant", 2500.0)
	await _year()
	await _state("policy-ev_grant-draft", main.popup.card)
	main.close_popup()
	await _settle()
	# Statistics: every fold of each.
	for key in ["indicator:gdp", "indicator:unemployment_rate", "indicator:budget_balance", "indicator:poverty_rate", "indicator:waiting_list"]:
		if not main.board.nodes.has(key):
			continue
		main.open_node(key)
		await _open()
		await _folds(key.replace(":", "-"))
		main.close_popup()
		await _settle()
	# A statistic off the board, and a cause followed (with Back).
	main.open_indicator("net_income_average")
	await _open()
	await _folds("statistic-off-board")
	main.close_popup()
	await _settle()
	main.open_node("indicator:budget_balance")
	await _open()
	var trace = main.current_trace()
	if trace != null:
		var link: Button = trace.find_child("*", true, false) as Button
		for b in trace.find_children("*", "Button", true, false):
			if (b as Button).theme_type_variation in ["Link", "LinkRow"] and (b as Button).is_visible_in_tree():
				link = b
				break
		if link != null:
			link.pressed.emit()
			await _open()
			await _state("statistic-followed", main.popup.card)
	main.close_popup()
	await _settle()
	# Groups of voters: counted from households, estimated, of belief.
	for key in ["group:pensioner", "group:motorists", "group:socialists", "group:young"]:
		if not main.board.nodes.has(key):
			continue
		main.open_node(key)
		await _open()
		if key == "group:pensioner":
			var until := Time.get_ticks_msec() + 30000
			while main.group_card() != null and main.group_card().records.is_empty() and Time.get_ticks_msec() < until:
				await process_frame
		await _folds(key.replace(":", "-"))
		if key == "group:pensioner" and not main.group_card().records.is_empty():
			main.group_card().household_opened.emit(main.group_card().records[0])
			await _open()
			await _state("group-pensioner-household", main.popup.card)
		main.close_popup()
		await _settle()
	# A situation: one in force if there is one, else the first.
	var situation := ""
	for entry in main.situations:
		if situation == "" or main.game.latest(str(entry["row"])) == true:
			situation = str(entry["name"])
			if main.game.latest(str(entry["row"])) == true:
				break
	if situation != "":
		main.open_situation(situation)
		await _open()
		await _folds("situation")
		main.close_popup()
		await _settle()


func _sheets() -> void:
	main.search_for("tax")
	await _open()
	await _screen("search")
	main.search.clear_search()
	main.search.release_focus()
	await _settle()
	main.open_overlay("budget")
	await _open()
	await _state("sheet-budget", main._budget_sheet.card)
	main.close_overlay()
	await _settle()
	main.open_overlay("parliament")
	await _open()
	for box in _fold_boxes(main._parliament_sheet):
		await _unfold(box)
		await _state("sheet-parliament-" + str(box.name).trim_prefix("fold_"), main._parliament_sheet.card)
	main.close_overlay()
	await _settle()
	main.open_add_policy()
	await _open()
	await _state("sheet-add-policy", main._add_sheet.card)
	main.close_overlay()
	await _settle()
	main.show_key()
	await _open()
	await _state("sheet-key", main._key_sheet.card)
	main._key_sheet.close()
	await _settle()
	main.menu_action("help")
	await _open()
	await _state("sheet-help", main._dialog.card)
	main._dialog.close()
	await _settle()
	# The month's report, with something to tell: a bill passed.
	if _view == SIZES[0] or only != 0:
		main.type_lever("basic_rate", 21.0)
		main.close_popup()
		await _settle()
		main.advance(1)
		await _settle()
		for d in main.unanswered_dilemmas():
			main.ask_dilemma()
			await _open()
			if main.dilemma_dialog != null and is_instance_valid(main.dilemma_dialog):
				await _state("sheet-question", main.dilemma_dialog.card)
			main.answer_dilemma(str(d["name"]), 1)
			await _settle()
	main.report.reopen()
	await _open()
	if main.report.visible:
		await _state("report", main.report)
	main.report.dismiss()
	await _settle()


# ---------------------------------------------------------------------------- one state

## The popup open now, with each of its folds opened in turn.
func _folds(name: String) -> void:
	var boxes := _fold_boxes(main.popup.card)
	if boxes.is_empty():
		await _state(name, main.popup.card)
		return
	for box in boxes:
		await _unfold(box)
		await _state("%s-%s" % [name, str(box.name).trim_prefix("fold_")], main.popup.card)


func _fold_boxes(under: Control) -> Array:
	return under.find_children("fold_*", "VBoxContainer", true, false).filter(func(b): return b.has_meta("fold") and b.is_visible_in_tree())


func _unfold(box: Control) -> void:
	var body: Control = box.get_child(1)
	if not body.visible:
		(box.get_child(0) as Button).pressed.emit()
	await _open()


## Checks one state's card and, with --shots, photographs it.
func _state(name: String, card: Control) -> void:
	_states += 1
	var tag := "%s at %dx%d" % [name, _view.x, _view.y]
	var view := Rect2(Vector2.ZERO, Vector2(_view))
	var grown := Time.get_ticks_msec() + 2000  # a card that opens by growing has grown
	while (not card.scale.is_equal_approx(Vector2.ONE) or Contrast.shown(card).a < 0.999) and Time.get_ticks_msec() < grown:
		await process_frame
	var rect := card.get_global_rect()
	if not card.scale.is_equal_approx(Vector2.ONE) or not card.is_visible_in_tree():
		_faults.append("%s: the card is not fully open" % tag)
		return
	if rect.position.x < 0.0 or rect.end.x > view.end.x + 0.5 or rect.end.y > view.end.y + 0.5 or rect.position.y < main.BAR_HEIGHT - 0.5:
		_faults.append("%s: the card %s is outside the window or over the top bar" % [tag, rect])
	for c in card.find_children("*", "Control", true, false):
		var control := c as Control
		if not control.is_visible_in_tree() or control.size.x <= 0.0:
			continue
		var r := control.get_global_rect()
		if _clipped_away(control):
			continue
		# Nothing pokes out of the card's sides.
		if r.position.x < rect.position.x - 1.0 or r.end.x > rect.end.x + 1.0:
			_faults.append("%s: %s (%s) pokes out of the card's sides: %.0f to %.0f, the card %.0f to %.0f" % [
				tag, _path(card, control), control.get_class(), r.position.x, r.end.x, rect.position.x, rect.end.x])
		if control is Label:
			var label := control as Label
			if label.text.strip_edges() == "":
				continue
			# Stage S19: no explainer notes. A piece of muted text is a caption, a unit or a
			# state, a few words long; a sentence of instruction or explanation is not put on a
			# card (the owner's rule, docs/PLAN.md). Words that are the model's own (a policy's or
			# a mod's description) are content, and say so with the meta "content".
			if label.get_theme_color("font_color").is_equal_approx(Contrast.Palette.MUTED) and not label.has_meta("content") \
					and label.text.strip_edges().length() > LONGEST_NOTE:
				var note := "a note of %d characters: \"%s…\"" % [label.text.strip_edges().length(), label.text.strip_edges().left(60)]
				if not _notes.has(note):
					_notes[note] = tag
					_faults.append("%s: %s" % [tag, note])
			var size_px := label.get_theme_font_size("font_size")
			if size_px < SMALLEST_TEXT:
				_faults.append("%s: \"%s\" is set at %d px" % [tag, label.text.left(40), size_px])
			# A label that does not wrap or trim needs the width of its words.
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF and not label.clip_text \
					and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and label.size.x + 0.5 < label.get_minimum_size().x:
				_faults.append("%s: \"%s\" has %.0f px, its words need %.0f" % [tag, label.text.left(40), label.size.x, label.get_minimum_size().x])
		elif control is Button:
			var button := control as Button
			if button.text.strip_edges() != "" and button.get_theme_font_size("font_size") < SMALLEST_TEXT:
				_faults.append("%s: the button \"%s\" is set at %d px" % [tag, button.text.left(40), button.get_theme_font_size("font_size")])
			if button.text.strip_edges() != "" and not button.clip_text and button.size.x + 0.5 < button.get_minimum_size().x:
				_faults.append("%s: the button \"%s\" has %.0f px, its words need %.0f" % [tag, button.text.left(40), button.size.x, button.get_minimum_size().x])
	# Stage S17.1: every piece of text in it against the ground it stands on.
	for line in Contrast.faults(card):
		_faults.append("%s: %s" % [tag, line])
	# Stage S18.1: every pictogram in it made at the size it is shown at.
	for line in Contrast.Palette.unsharp(card):
		_faults.append("%s: %s" % [tag, line])
	if shots == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var crop := Rect2i(rect.grow(18.0)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(crop).save_png(shots.path_join("%d-%s.png" % [_view.x, name]))


## With --shots, the whole screen as it stands (the board, the top bar, what is open).
func _screen(name: String) -> void:
	if shots == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(12)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shots.path_join("%d-screen-%s.png" % [_view.x, name]))


## True when a scroll container between `control` and the card hides it (scrolled out of
## view): what is not shown cannot poke out.
func _clipped_away(control: Control) -> bool:
	var r := control.get_global_rect()
	var up := control.get_parent()
	while up != null and up is Control:
		if up is ScrollContainer or (up as Control).clip_contents:
			if not (up as Control).get_global_rect().grow(1.0).intersects(r):
				return true
		up = up.get_parent()
	return false


func _path(from: Control, to: Control) -> String:
	return str(from.get_path_to(to)).right(70)


# ---------------------------------------------------------------------------- waiting

## Until a popup or sheet just opened (or a fold in it) has grown and laid itself out.
func _open() -> void:
	await _settle()
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until:
		var card: Control = main.popup.card
		if not main.popup.is_open() or (card.scale.is_equal_approx(Vector2.ONE) and card.modulate.a >= 0.999):
			break
		await process_frame
	await _frames(8)


## Until the open policy popup's year ahead is in.
func _year() -> void:
	var card = main.policy_card()
	card.year_shown = []
	var until := Time.get_ticks_msec() + 30000
	while card.year_shown.is_empty() and Time.get_ticks_msec() < until:
		await process_frame
	await _frames(8)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 4:
		await process_frame
