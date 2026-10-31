extends Node
## Player preferences: text speed, auto-advance speed, volumes, fullscreen.
## Registered as the `Settings` autoload in project.godot. Shared by all save slots; stored in
## `path` (a ConfigFile). Every change applies at once; call save() to keep it.
##
## Speeds and volumes are 0..1 slider positions. Use seconds_per_char() and auto_delay_scale()
## instead of reading the speed values directly.

signal changed(key: StringName)

const SECTION := "settings"
const DEFAULTS: Dictionary = {
	&"text_speed": 0.5,
	&"auto_speed": 0.5,
	&"master_volume": 0.8,
	&"music_volume": 0.8,
	&"sfx_volume": 0.8,
	&"voice_volume": 0.8,
	&"fullscreen": false,
}
## Volume setting -> audio bus (see default_bus_layout.tres). Ambience goes through SFX.
const VOLUME_BUSES: Dictionary = {
	&"master_volume": &"Master",
	&"music_volume": &"Music",
	&"sfx_volume": &"SFX",
	&"voice_volume": &"Voice",
}
## Typing delay per character at the slowest and fastest (before instant) text speed.
const SLOWEST_CHAR_SECONDS := 0.08
const FASTEST_CHAR_SECONDS := 0.005
## Auto-advance delay multiplier at the slowest and fastest auto speed.
const SLOWEST_AUTO_SCALE := 2.0
const FASTEST_AUTO_SCALE := 0.5

## Where settings are stored. Tests point this somewhere else.
var path: String = "user://settings.cfg"

var _values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	load_settings()


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Sets and applies one setting. Unknown keys and values of the wrong type are ignored;
## speeds and volumes are clamped to 0..1.
func set_value(key: StringName, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown setting %s" % key)
		return
	var default: Variant = DEFAULTS[key]
	if default is float and (value is float or value is int):
		value = clampf(float(value), 0.0, 1.0)
	elif typeof(value) != typeof(default):
		push_warning("Settings: wrong type for %s: %s" % [key, value])
		return
	_values[key] = value
	_apply(key)
	changed.emit(key)


func reset_to_defaults() -> void:
	for key: StringName in DEFAULTS:
		set_value(key, DEFAULTS[key])


## Seconds to type one character (DialogueLabel.seconds_per_step). 0 means instant.
func seconds_per_char() -> float:
	var t: float = get_value(&"text_speed")
	if t >= 1.0:
		return 0.0
	return SLOWEST_CHAR_SECONDS * pow(FASTEST_CHAR_SECONDS / SLOWEST_CHAR_SECONDS, t)


## Multiplier for auto-advance delays: 1.0 at the default speed, larger is slower.
func auto_delay_scale() -> float:
	var t: float = get_value(&"auto_speed")
	return SLOWEST_AUTO_SCALE * pow(FASTEST_AUTO_SCALE / SLOWEST_AUTO_SCALE, t)


func save() -> Error:
	var config := ConfigFile.new()
	for key: StringName in _values:
		config.set_value(SECTION, String(key), _values[key])
	return config.save(path)


## Loads saved settings over the defaults and applies them. A missing or broken file leaves
## the defaults.
func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK and config.has_section(SECTION):
		for key: String in config.get_section_keys(SECTION):
			if DEFAULTS.has(StringName(key)):
				set_value(StringName(key), config.get_value(SECTION, key))
	for key: StringName in DEFAULTS:
		_apply(key)


func _apply(key: StringName) -> void:
	if VOLUME_BUSES.has(key):
		var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus < 0:
			return
		var volume: float = _values[key]
		AudioServer.set_bus_mute(bus, volume <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	elif key == &"fullscreen":
		if DisplayServer.get_name() == "headless":
			return
		var fullscreen: bool = _values[key]
		var is_fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen != is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
