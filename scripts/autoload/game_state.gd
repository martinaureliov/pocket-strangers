extends Node
## Global story state: current episode, completed episodes, story flags, read lines, and the
## position inside the current scene (for save-anywhere).
## Registered as the `GameState` autoload in project.godot.

signal flag_changed(key: StringName, value: Variant)
signal episode_completed(episode_id: StringName)

const SAVE_PATH := "user://save.json"
## v1: current_episode, completed_episodes, flags.
## v2: + scene (save-anywhere position + stage), seen_lines.
const SAVE_VERSION := 2
const EPISODE_PATHS: Array[String] = [
	"res://episodes/ep01/episode.tres",
	"res://episodes/ep02/episode.tres",
	"res://episodes/ep03/episode.tres",
	"res://episodes/ep04/episode.tres",
	"res://episodes/ep05/episode.tres",
]

var current_episode: StringName = &""
var completed_episodes: Array[StringName] = []
var flags: Dictionary = {}
## Where the player is inside the current episode. Written by the VN player before saving,
## read back on load. Empty when not inside an episode.
var scene_state: Dictionary = {}
## Lines the player has already read, as a set (key -> true). Used by skip mode.
var seen_lines: Dictionary = {}


func get_episodes() -> Array[Episode]:
	var result: Array[Episode] = []
	for path in EPISODE_PATHS:
		var ep := load(path) as Episode
		if ep:
			result.append(ep)
		else:
			push_error("GameState: could not load episode at %s" % path)
	return result


func get_episode(episode_id: StringName) -> Episode:
	for ep in get_episodes():
		if ep.id == episode_id:
			return ep
	return null


## Call when starting an episode from its beginning.
func begin_episode(episode_id: StringName) -> void:
	current_episode = episode_id
	scene_state = {}


func set_flag(key: StringName, value: Variant = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: StringName, default: Variant = null) -> Variant:
	return flags.get(key, default)


func has_flag(key: StringName) -> bool:
	return flags.has(key)


func complete_episode(episode_id: StringName) -> void:
	if episode_id not in completed_episodes:
		completed_episodes.append(episode_id)
	episode_completed.emit(episode_id)


func is_episode_completed(episode_id: StringName) -> bool:
	return episode_id in completed_episodes


func mark_line_seen(line_key: String) -> void:
	seen_lines[line_key] = true


func is_line_seen(line_key: String) -> bool:
	return seen_lines.has(line_key)


func reset() -> void:
	current_episode = &""
	completed_episodes.clear()
	flags.clear()
	scene_state = {}
	seen_lines.clear()


func to_dict() -> Dictionary:
	var completed: Array[String] = []
	for id in completed_episodes:
		completed.append(String(id))
	var flag_data := {}
	for key in flags:
		flag_data[String(key)] = flags[key]
	return {
		"version": SAVE_VERSION,
		"current_episode": String(current_episode),
		"completed_episodes": completed,
		"flags": flag_data,
		"scene": scene_state.duplicate(true),
		"seen_lines": seen_lines.keys(),
	}


func from_dict(data: Dictionary) -> void:
	data = migrate(data)
	reset()
	current_episode = StringName(data.get("current_episode", ""))
	for id in data.get("completed_episodes", []):
		completed_episodes.append(StringName(id))
	var flag_data: Dictionary = data.get("flags", {})
	for key in flag_data:
		flags[StringName(key)] = flag_data[key]
	scene_state = data.get("scene", {})
	for line_key: Variant in data.get("seen_lines", []):
		seen_lines[String(line_key)] = true


## Upgrade save data from older versions to SAVE_VERSION, one step at a time.
static func migrate(data: Dictionary) -> Dictionary:
	data = data.duplicate(true)
	var version := int(data.get("version", 1))  # JSON numbers load as float
	if version < 2:
		data["scene"] = {}
		data["seen_lines"] = []
		version = 2
	data["version"] = version
	return data


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## Crash-safe save: write a temp file, keep the previous save as .bak, then rename.
func save_game(path: String = SAVE_PATH) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if not file.store_string(JSON.stringify(to_dict(), "\t")):
		file.close()
		return ERR_FILE_CANT_WRITE
	file.close()
	if FileAccess.file_exists(path):
		var backup_err := DirAccess.rename_absolute(path, path + ".bak")
		if backup_err != OK:
			return backup_err
	return DirAccess.rename_absolute(tmp, path)


## Loads `path`, falling back to its .bak if the main file is missing or unreadable.
func load_game(path: String = SAVE_PATH) -> Error:
	var result := ERR_FILE_NOT_FOUND
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if parsed is Dictionary:
			from_dict(parsed)
			return OK
		result = ERR_PARSE_ERROR
	return result


func delete_save(path: String = SAVE_PATH) -> void:
	for candidate: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
