extends Node
## Global story state: current episode, completed episodes, and story flags.
## Registered as the `GameState` autoload in project.godot.

signal flag_changed(key: StringName, value: Variant)
signal episode_completed(episode_id: StringName)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
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


func get_episodes() -> Array[Episode]:
	var result: Array[Episode] = []
	for path in EPISODE_PATHS:
		var ep := load(path) as Episode
		if ep:
			result.append(ep)
		else:
			push_error("GameState: could not load episode at %s" % path)
	return result


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


func reset() -> void:
	current_episode = &""
	completed_episodes.clear()
	flags.clear()


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
	}


func from_dict(data: Dictionary) -> void:
	reset()
	current_episode = StringName(data.get("current_episode", ""))
	for id in data.get("completed_episodes", []):
		completed_episodes.append(StringName(id))
	var flag_data: Dictionary = data.get("flags", {})
	for key in flag_data:
		flags[StringName(key)] = flag_data[key]


func save_game(path: String = SAVE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func load_game(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	from_dict(parsed)
	return OK
