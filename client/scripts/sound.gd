extends RefCounted
## Stage S13.6: the interface's few sounds, quiet and short (client/sounds, Kenney's
## "Interface Sounds", CC0). One player per sound, made the first time it is wanted; the
## pointer's tick and a slider's click are rate-limited so sweeping the board or dragging
## does not rattle. Nothing plays, and no player is made, without a display (headless runs)
## or with the sound off. On or off and the volume are kept in user://settings.cfg.

const FILES := {"tick": "tick_002", "open": "open_001", "close": "close_001", "change": "click_002",
	"bill": "confirmation_001", "withdraw": "back_001", "month": "pluck_001", "notice": "error_004",
	"question": "question_001", "election": "bong_001"}
## Each sound's level against the others: the tick, heard most, is the softest.
const LEVEL := {"tick": 0.35, "change": 0.5, "open": 0.6, "close": 0.5}
## The least time between two plays of a sound, in milliseconds.
const GAP := {"tick": 110, "change": 90}
const SETTINGS := "user://settings.cfg"

static var enabled := true
static var volume := 0.5
## The sounds asked for, latest last (the last 32), heard or not: for the checks.
static var asked: PackedStringArray = []
static var _players := {}
static var _last := {}


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		enabled = bool(config.get_value("sound", "on", true))
		volume = clampf(float(config.get_value("sound", "volume", 0.5)), 0.0, 1.0)


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("sound", "on", enabled)
	config.set_value("sound", "volume", volume)
	config.save(SETTINGS)


## True when a sound would be heard: a display, the sound on and some volume.
static func audible() -> bool:
	return enabled and volume > 0.0 and DisplayServer.get_name() != "headless"


static func play(name: String) -> void:
	if not FILES.has(name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < int(GAP.get(name, 40)):
		return
	_last[name] = now
	asked.append(name)
	if asked.size() > 32:
		asked = asked.slice(asked.size() - 32)
	if not audible():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var player: AudioStreamPlayer = _players.get(name)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		player.stream = load("res://sounds/%s.ogg" % FILES[name])
		tree.root.add_child(player)
		_players[name] = player
	player.volume_db = linear_to_db(volume * float(LEVEL.get(name, 0.8)))
	player.play()


## For the checks: how many players exist (none in a headless run).
static func players() -> int:
	return _players.values().filter(func(p): return is_instance_valid(p)).size()
