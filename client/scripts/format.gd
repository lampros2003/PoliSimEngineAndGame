extends RefCounted
## Numbers and dates for people. Values arrive as the engine stores them: money in minor
## units (such as pence), rates as fractions, flows per step. With `per_year` on, flows
## are shown at an annual rate (a month's flow times twelve), which is how published
## accounts and budgets are given.

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]

var minor := 100
var symbol := ""
var currency := ""
var start_year := 2027
var start_month := 0  # 0 = January
var step_unit := "month"
var steps_per_year := 12
var per_year := false

const STEPS_PER_YEAR := {"month": 12, "quarter": 4, "year": 1, "week": 52}


func configure(catalogue: Dictionary, play: Dictionary) -> void:
	minor = int(catalogue.get("minor", 100))
	currency = str(catalogue.get("currency", ""))
	symbol = str(play.get("currency_symbol", currency))
	step_unit = str(catalogue.get("step_unit", "month"))
	steps_per_year = int(STEPS_PER_YEAR.get(step_unit, 1))
	var start := str(play.get("start", "2027-01")).split("-")
	if start.size() == 2:
		start_year = int(start[0])
		start_month = clampi(int(start[1]) - 1, 0, 11)


## The month a step covers: step 0 is the start month.
func month_name(step: int, short := false) -> String:
	var index := start_month + step
	var name: String = MONTHS[posmod(index, 12)]
	if short:
		name = name.substr(0, 3)
	return "%s %d" % [name, start_year + floori(index / 12.0)]


static func grouped(value: float, decimals := 0) -> String:
	var negative := value < 0.0
	var text := String.num(absf(value), decimals)
	if decimals > 0 and not text.contains("."):
		text += "." + "0".repeat(decimals)
	elif decimals > 0:
		var have := text.length() - text.find(".") - 1
		text += "0".repeat(maxi(0, decimals - have))
	var whole := text.get_slice(".", 0)
	var rest := text.substr(whole.length())
	var out := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			out += ","
		out += whole[i]
	return (MINUS if negative else "") + out + rest


## A major-unit amount in a short form: 39.12bn, 812.4m, 12,500, 800.50.
static func compact(amount: float) -> String:
	var size := absf(amount)
	if size >= 1e12:
		return "%.2ftn" % (amount / 1e12)
	if size >= 1e9:
		return "%.2fbn" % (amount / 1e9)
	if size >= 1e6:
		return "%.1fm" % (amount / 1e6)
	if size >= 1e4 or is_equal_approx(amount, roundf(amount)):
		return grouped(roundf(amount))
	return grouped(amount, 2)


## The symbol and the amount: "£12.38bn", but "Cr 12.38bn" for a symbol ending in a letter.
func with_symbol(amount_text: String) -> String:
	if symbol == "":
		return amount_text
	var last := symbol.unicode_at(symbol.length() - 1)
	var letter := (last >= 65 and last <= 90) or (last >= 97 and last <= 122)
	return symbol + (" " if letter else "") + amount_text


# A true minus sign, joined to what follows so a line never breaks between them.
const MINUS := "\u2212\u2060"


func money(minor_units: float) -> String:
	var amount := minor_units / float(minor)
	var sign := MINUS if amount < 0.0 else ""
	return sign + with_symbol(compact(absf(amount)))


## True when a unit is an amount per step, such as GBP/month.
func is_flow(unit: String) -> bool:
	var parts := unit.split("/")
	for i in range(1, parts.size()):
		if parts[i] == step_unit:
			return true
	return false


## What a stored value is multiplied by for display: twelve for a monthly flow shown a
## year, otherwise one. `shown` picks the unit of totals, as in value().
func factor(entry: Dictionary, shown := true) -> float:
	if not per_year or is_rate(entry):
		return 1.0
	var unit: String = entry.get("shown_unit" if shown else "unit", "1")
	return float(steps_per_year) if is_flow(unit) else 1.0


static func percent(fraction: float, decimals := 1) -> String:
	return String.num(fraction * 100.0, decimals) + "%"


## Describes the part of a unit that is not the currency: " a month", " per household".
func unit_words(unit: String) -> String:
	var parts := unit.split("/")
	var words := PackedStringArray()
	var top := parts[0]
	if top == "person":
		words.append("people")
	elif top != "1" and top != currency:
		words.append(top + ("s" if not top.ends_with("s") else ""))
	for i in range(1, parts.size()):
		var bottom := parts[i]
		if per_year and bottom == step_unit:
			words.append("a year")
		elif bottom == "month" or bottom == "year" or bottom == "quarter":
			words.append("a " + bottom)
		else:
			words.append("per " + bottom)
	return "" if words.is_empty() else " " + " ".join(words)


## True for a number of people (unit "person"): its changes are shown in whole people.
static func is_count(entry: Dictionary) -> bool:
	return str(entry.get("unit", "")) == "person"


## True for an amount of money: a `money` value, or a real whose unit is the currency (an
## average income, say), which the engine also holds in minor units.
func is_money(entry: Dictionary) -> bool:
	if entry.get("money", false):
		return true
	return currency != "" and entry.get("type", "") == "real" and str(entry.get("unit", "")).split("/")[0] == currency


## True for a dimensionless real, which reads best as a percentage.
static func is_rate(entry: Dictionary) -> bool:
	return entry.get("type", "") == "real" and str(entry.get("unit", "")) == "1"


## A value with its unit, as the entry describes it. `shown` uses the total's unit.
## `scaled` means `v` has already been multiplied by factor().
func value(entry: Dictionary, v: Variant, shown := true, with_unit := true, scaled := false) -> String:
	if v == null:
		return "–"
	var unit: String = entry.get("shown_unit" if shown else "unit", "1")
	var text := ""
	if typeof(v) != TYPE_BOOL and not scaled:
		var k := factor(entry, shown)
		if k != 1.0:
			v = v * int(k) if typeof(v) == TYPE_INT else float(v) * k
	if typeof(v) == TYPE_BOOL:
		text = "yes" if v else "no"
	elif is_money(entry):
		text = money(float(v))
	elif is_rate(entry):
		return percent(float(v))
	elif typeof(v) == TYPE_INT:
		text = grouped(float(v))
	else:
		var f := float(v)
		if is_count(entry) and absf(f) < 1e8:
			text = grouped(roundf(f))
		else:
			text = grouped(f, 2) if absf(f) < 1e4 else compact(f)
	return text + (unit_words(unit) if with_unit else "")


## A change, always signed.
func change(entry: Dictionary, delta: Variant) -> String:
	if delta == null:
		return "–"
	var d := float(delta) * factor(entry)
	if d == 0.0:
		return "no change"
	var sign := "+" if d > 0.0 else MINUS
	if is_money(entry):
		return sign + with_symbol(compact(absf(d) / float(minor)))
	if is_rate(entry):
		return sign + String.num(absf(d) * 100.0, 2) + " pts"
	if typeof(delta) == TYPE_INT:
		return sign + grouped(absf(d))
	if is_count(entry):
		return sign + (grouped(roundf(absf(d))) if absf(d) < 1e6 else compact(absf(d)))
	return sign + (grouped(absf(d), 3) if absf(d) < 1e4 else compact(absf(d)))
