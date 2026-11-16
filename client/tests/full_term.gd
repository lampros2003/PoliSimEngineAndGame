extends SceneTree
## A full term of the UK (models/uk/scenarios/2025.toml), played through main.gd's methods as
## a player would: a fixed script of decisions over the 60 months (taxes up and down, spending,
## three policies introduced in three areas and one refused for want of capital, level
## policies, a repeal) and every question answered as it comes, with a popup of each kind and
## both sheets opened along the way. It proves: no failed month; every bill's fate is what the
## report says (passed or refused), with the capital spent, earned and held adding up and
## never negative; the month's report after every month (stage S14.1: open over the board
## for a month with bills, else its one line under the date); the election in July
## 2029 with its result announced; and a game saved in month 24 and loaded plays months 24 to
## 36 again to the same state hashes and headline figures.

## Decisions by the month they are made in (months run so far): ["type", lever, value in the
## lever's own terms], ["scale", lever, factor] (a money lever times factor), ["introduce",
## policy, value], ["repeal", policy].
const PLAN := {
	2: [["type", "fuel_duty", 57.95]],
	3: [["introduce", "policy:ev_grant", 2500.0]],
	5: [["scale", "spending_health", 1.05]],
	7: [["type", "basic_rate", 21.0]],
	9: [["type", "sentencing", 3.0]],
	11: [["introduce", "policy:insulation_programme", 100000000.0]],
	13: [["type", "corporation_tax_rate", 24.0]],
	15: [["type", "personal_allowance", 13000.0]],
	17: [["introduce", "policy:social_housing", 200000000.0]],
	# Three bills in one month (the first made after the save): the third costs more than is
	# left, and is refused.
	24: [["scale", "spending_defence", 1.05], ["type", "planning_rules", 3.0], ["introduce", "policy:rent_controls", 2.0]],
	30: [["repeal", "policy:ev_grant"]],
	34: [["type", "tobacco_duty", 1.2]],
	36: [["scale", "benefits_bill", 1.03]],
	42: [["type", "free_school_meals", 1.0]],
	45: [["type", "fuel_duty", 55.95]],
	47: [["type", "child_benefit_eldest", 1400.0]],
	49: [["type", "vat_rate", 19.0]],
	51: [["type", "personal_allowance", 13500.0]],
	53: [["scale", "spending_health", 1.03]],
}
## Answers other than the first, by question.
const ANSWERS := {"pay_claim": 2, "defence_summit": 2, "prisons_full": 2, "energy_shock": 2}
const SAVE_AT := 24
const COMPARE_AT := 36
const ELECTION := "July 2029"

var main: Control
var save_file := ""
var seen := 0  # changes already checked
var questions := 0
var bills := {"passed": 0, "refused": 0}
var refused := PackedStringArray()
var election_seats := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	if main.failed or main.game.steps_done() != 0:
		return _fail("the game did not start")
	save_file = ProjectSettings.globalize_path("user://full_term_check.psave")
	main.save_path = save_file
	var hashes_through := PackedStringArray()
	var headline_through := {}
	var replayed := false
	while main.game.steps_done() < main.term:
		var month: int = main.game.steps_done()
		if month == SAVE_AT and not replayed:
			main.save_game()
			await _settle()
			if not FileAccess.file_exists(save_file):
				return _fail("no save after month %d" % month)
		if month == COMPARE_AT and not replayed:
			hashes_through = main.game.hashes()
			headline_through = _headline()
			main.load_game()
			await _settle()
			if main.game.steps_done() != SAVE_AT or main.failed:
				return _fail("loading the save gave month %d" % main.game.steps_done())
			seen = main.game.changes().size()
			replayed = true
			continue
		if not await _decide(month):
			return
		if not await _month():
			return
		if main.game.steps_done() == COMPARE_AT and replayed:
			var again: PackedStringArray = main.game.hashes()
			if again.slice(0, COMPARE_AT) != hashes_through.slice(0, COMPARE_AT) or _headline() != headline_through:
				return _fail("saved in month %d and loaded, month %d differs: %s against %s" % [SAVE_AT, COMPARE_AT, _headline(), headline_through])
		if not await _look_around(main.game.steps_done()):
			return
	# The end of the term: the summary, the election once, in its month.
	if bills["passed"] < 15:
		return _fail("only %d bills passed: %s refused" % [bills["passed"], refused])
	var elections := Array(main.game.series("election_now")).filter(func(v): return v >= 0.5).size()
	if elections != 1 or main.term_announced != true or not str(main._dialog.title).begins_with("End of term"):
		return _fail("after the term: %d elections, term announced %s" % [elections, main.term_announced])
	DirAccess.remove_absolute(save_file)
	print("full term: 60 months, %d bills passed and %d refused as announced (months %d to %d twice; refused: %s), %d questions answered, the election in %s won with %d seats, capital %.1f at the end; saved in month %d and loaded, month %d identical" % [
		bills["passed"], bills["refused"], SAVE_AT, COMPARE_AT, ", ".join(refused), questions, ELECTION, election_seats, _capital(), SAVE_AT, COMPARE_AT])
	quit(0)


## Makes the month's decisions through the policies' popups.
func _decide(month: int) -> bool:
	for action in PLAN.get(month, []):
		match str(action[0]):
			"type":
				main.type_lever(action[1], action[2])
			"scale":
				main.type_lever(action[1], float(main.game.latest(action[1])) / main.fmt.minor * float(action[2]))
			"introduce":
				if main.introduce_policy(action[1], action[2]) == "" or not main.board.nodes.get(action[1], {}).get("ghost", false):
					return _bad("month %d: %s was not put to the Commons as a ghost" % [month, action[1]])
			"repeal":
				main.repeal_policy(action[1])
		await _settle()
		main.close_popup()
	var waiting: Array = main.game.pending().keys().filter(func(k): return main.board.holds(str(k)) != "")
	if waiting.size() != PLAN.get(month, []).size():
		return _bad("month %d: %d bills waiting, not %d: %s" % [month, waiting.size(), PLAN.get(month, []).size(), main.game.pending()])
	return true


## Runs a month and checks it: the bills' fates, the capital, the report, the election and
## the questions, answered as they come.
func _month() -> bool:
	var before := _capital()
	main.advance(1)
	await _settle()
	var month: int = main.game.steps_done() - 1
	var name: String = main.fmt.month_name(month)
	if main.failed or main.game.steps_done() != month + 1:
		return _bad("%s did not run: %s" % [name, main.notice_text()])
	# Every bill as announced; what passed is in force and what it cost was spent.
	var changes: Array = main.game.changes()
	var cost := 0.0
	var lines: PackedStringArray = main.report.lines_shown
	var said := {"passed": 0, "refused": 0}
	for line in lines:
		if line.contains(": refused, it needed"):
			said["refused"] += 1
		elif line.ends_with(": passed") or line.contains(" introduced at ") or line.ends_with(" repealed"):
			said["passed"] += 1
	var put := {"passed": 0, "refused": 0}
	for i in range(seen, changes.size()):
		var c: Dictionary = changes[i]
		if main.board.holds(str(c["lever"])) == "":
			continue  # an answer to a question
		var now := float(main.game.latest(str(c["lever"])))
		if c.get("refused", false):
			put["refused"] += 1
			refused.append("%s in %s" % [c["lever"], name])
			if not main.report.visible or absf(now - float(c["value"])) < 1e-9:
				return _bad("%s: %s refused, but the report is %s and it stands at %s" % [name, c["lever"], main.report.visible, now])
		elif c.get("passed", true):
			put["passed"] += 1
			cost += float(c["cost"])
			if absf(now - float(c["value"])) > 1e-6:
				return _bad("%s: %s passed at %s but stands at %s" % [name, c["lever"], c["value"], now])
		else:
			return _bad("%s: %s voted down with 411 seats" % [name, c["lever"]])
	seen = changes.size()
	if said != put:
		return _bad("%s: the report says %s, the Commons did %s: %s" % [name, said, put, lines])
	bills["passed"] += put["passed"]
	bills["refused"] += put["refused"]
	var spent := float(main.game.latest("capital_spent"))
	var earned := float(main.game.latest("capital_earned"))
	var after := _capital()
	if after < 0.0 or absf(spent - cost) > 1e-6 or (before >= 0.0 and spent > before + 1e-9) or before >= 0.0 and absf(after - clampf(before - spent + earned, 0.0, 100.0)) > 1e-6:
		return _bad("%s: capital %.3f, spent %.3f (bills %.3f), earned %.3f, now %.3f" % [name, before, spent, cost, earned, after])
	# The month's report, every month after the base one.
	var told: bool = main.report.visible or main.notice_text().begins_with(name + ":")
	if month > 0 and (main.report.title != name or not told or (put["passed"] + put["refused"] > 0 and not main.report.visible)):
		return _bad("%s: no report (%s, shown %s, line %s)" % [name, main.report.title, main.report.visible, main.notice_text()])
	# The election, in its month only, and its result.
	var election: bool = main.game.latest("election_now") == true
	if election != (name == ELECTION):
		return _bad("%s: election %s" % [name, election])
	if election:
		election_seats = int(main.game.latest("government_seats"))
		var title := str(main._dialog.title) if main._dialog != null and is_instance_valid(main._dialog) else ""
		if not title.begins_with("Election night") or main.lost != (title != "Election night"):
			return _bad("%s: the election's sheet reads %s" % [name, title])
		if main.lost:
			return _bad("the script's government lost the election, with %d seats" % election_seats)
		main._dialog.close()
	# Questions, as they come: each asked on its sheet, answered, and flagged.
	while not main.unanswered_dilemmas().is_empty():
		var d: Dictionary = main.unanswered_dilemmas()[0]
		var key := str(d["name"])
		if main.dilemma_title() != str(d["label"]):
			return _bad("%s: %s waits, but the sheet shows %s" % [name, key, main.dilemma_title()])
		if main.can_advance() and not main.game.is_busy():
			main.advance(1)  # refused while a question waits
			await _settle()
			if main.game.steps_done() != month + 1:
				return _bad("%s: a month ran while %s waited" % [name, key])
		var answer: int = ANSWERS.get(key, 1)
		main.answer_dilemma(key, answer)
		await _settle()
		questions += 1
		var option := str(d["options"][answer - 1]["label"])
		if not main.flag_text("dilemma_" + key).contains(option):
			return _bad("%s: answered %s, the flag reads %s" % [name, option, main.flag_text("dilemma_" + key)])
	return true


## A popup of each kind and both sheets, once each over the term.
func _look_around(months: int) -> bool:
	match months:
		3:
			main.open_node("indicator:gdp")
			await _settle()
			if not _expect("indicator", "GDP's popup"):
				return false
		4:
			main.open_node("group:pensioner")
			var card = main.group_card()
			var until := Time.get_ticks_msec() + 20000
			while card.records.is_empty() and Time.get_ticks_msec() < until:
				await process_frame
			if card.records.is_empty():
				return _bad("no households for pensioners")
			card.household_opened.emit(card.records[0])
			await _settle()
			if not _expect("household", "a pensioner household"):
				return false
		6:
			main.open_introduce("Housing")
			await _settle()
			if not _expect("introduce", "Housing's list"):
				return false
		8:
			main.open_node("policy:nhs")
			await _settle()
			if not _expect("policy", "the NHS"):
				return false
		10:
			main.open_overlay("budget")
			await _settle()
			if main.overlay_open() != "budget":
				return _bad("the Budget did not open")
			main.close_overlay()
		56:
			main.open_overlay("parliament")
			await _settle()
			if main.overlay_open() != "parliament":
				return _bad("Parliament did not open")
			main.close_overlay()
	main.close_popup()
	return true


func _expect(kind: String, what: String) -> bool:
	return main.popup_kind() == kind or _bad("%s opened %s, not %s" % [what, main.popup_kind(), kind])


## The capital held after the last month (-1 before the first).
func _capital() -> float:
	var held: Variant = main.game.latest("political_capital")
	return -1.0 if held == null else float(held)


func _headline() -> Dictionary:
	var out := {}
	for row in ["government_support", "gdp", "unemployment_rate", "consumer_inflation_annual", "budget_balance", "debt_to_gdp", "political_capital"]:
		out[row] = main.game.latest(row)
	return out


func _fail(message: String) -> void:
	push_error(message)
	DirAccess.remove_absolute(save_file)
	quit(1)


## Fails, for a check that returns whether to go on.
func _bad(message: String) -> bool:
	_fail(message)
	return false


func _settle() -> void:
	for i in 4:
		await process_frame
	while main.game.is_busy() or main.advance_queued():
		await process_frame
	for i in 4:
		await process_frame
