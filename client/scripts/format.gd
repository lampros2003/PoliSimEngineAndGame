extends RefCounted
## Numbers and dates for people. Values arrive as the engine stores them: money in minor
## units (such as pence), rates as fractions.

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]

var minor := 100
var symbol := ""
var currency := ""
var start_year := 2027
var start_month := 0  # 0 = January


func configure(catalogue: Dictionary, play: Dictionary) -> void:
	minor = int(catalogue.get("minor", 100))
	currency = str(catalogue.get("currency", ""))
	symbol = str(play.get("currency_symbol", currency))
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
	return ("-" if negative else "") + out + rest


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


func money(minor_units: float) -> String:
	var amount := minor_units / float(minor)
	var sign := "-" if amount < 0.0 else ""
	return "%s%s %s" % [sign, symbol, compact(absf(amount))]


static func percent(fraction: float, decimals := 1) -> String:
	return String.num(fraction * 100.0, decimals) + "%"


## Describes the part of a unit that is not the currency: " a month", " per household".
func unit_words(unit: String) -> String:
	var parts := unit.split("/")
	var words := PackedStringArray()
	var top := parts[0]
	if top != "1" and top != currency:
		words.append(top + ("s" if not top.ends_with("s") else ""))
	for i in range(1, parts.size()):
		var bottom := parts[i]
		if bottom == "month" or bottom == "year" or bottom == "quarter":
			words.append("a " + bottom)
		else:
			words.append("per " + bottom)
	return "" if words.is_empty() else " " + " ".join(words)


## True for a dimensionless real, which reads best as a percentage.
static func is_rate(entry: Dictionary) -> bool:
	return entry.get("type", "") == "real" and str(entry.get("unit", "")) == "1"


## A value with its unit, as the entry describes it. `shown` uses the total's unit.
func value(entry: Dictionary, v: Variant, shown := true, with_unit := true) -> String:
	if v == null:
		return "–"
	var unit: String = entry.get("shown_unit" if shown else "unit", "1")
	var text := ""
	if typeof(v) == TYPE_BOOL:
		text = "yes" if v else "no"
	elif entry.get("money", false):
		text = money(float(v))
	elif is_rate(entry):
		return percent(float(v))
	elif typeof(v) == TYPE_INT:
		text = grouped(float(v))
	else:
		var f := float(v)
		text = grouped(f, 2) if absf(f) < 1e4 else compact(f)
	return text + (unit_words(unit) if with_unit else "")


## A change, always signed.
func change(entry: Dictionary, delta: Variant) -> String:
	if delta == null:
		return "–"
	var d := float(delta)
	if d == 0.0:
		return "no change"
	var sign := "+" if d > 0.0 else "-"
	if entry.get("money", false):
		return sign + symbol + " " + compact(absf(d) / float(minor))
	if is_rate(entry):
		return sign + String.num(absf(d) * 100.0, 2) + " pts"
	if typeof(delta) == TYPE_INT:
		return sign + grouped(absf(d))
	return sign + (grouped(absf(d), 3) if absf(d) < 1e4 else compact(absf(d)))
