extends Node
## Global story state: current episode, completed episodes, story flags, read lines, and the
## position inside the current scene (for save-anywhere).
## Registered as the `GameState` autoload in project.godot.
##
## Saves: one file per slot in `save_dir` (the autosave slot plus SLOT_COUNT manual slots).
## Read lines are shared by all slots and live in the system file, so skip mode knows what the
## player has read no matter which slot they load.

signal flag_changed(key: StringName, value: Variant)
signal episode_completed(episode_id: StringName)

## v1: current_episode, completed_episodes, flags.
## v2: + scene (save-anywhere position + stage), seen_lines.
## v3: one file per slot, + meta (saved_at, preview) for the slot list; seen_lines moved to
##     the system file.
const SAVE_VERSION := 3
const SYSTEM_VERSION := 1
const SLOT_COUNT := 9
## Written by the game at safe points (end of an episode); the player can't save over it.
const AUTO_SLOT := "auto"
## The single save file used before save slots existed.
const LEGACY_SAVE_PATH := "user://save.json"
const EPISODE_PATHS: Array[String] = [
	"res://episodes/ep01/episode.tres",
	"res://episodes/ep02/episode.tres",
	"res://episodes/ep03/episode.tres",
	"res://episodes/ep04/episode.tres",
	"res://episodes/ep05/episode.tres",
]

## Where slot files and the system file live. Tests point these somewhere else.
var save_dir: String = "user://saves"
var system_path: String = "user://system.json"

var current_episode: StringName = &""
var completed_episodes: Array[StringName] = []
var flags: Dictionary = {}
## Where the player is inside the current episode. Written by the VN player before saving,
## read back on load. Empty when not inside an episode.
var scene_state: Dictionary = {}
## Lines the player has already read, as a set (key -> true). Used by skip mode.
## Shared by all slots: saved in the system file, not in slots.
var seen_lines: Dictionary = {}

var _bbcode := RegEx.create_from_string("\\[[^\\]]*\\]")


func _ready() -> void:
	migrate_legacy_save()
	load_system()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_system()


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


func clear_seen_lines() -> void:
	seen_lines.clear()


## Clears story progress. Read lines are shared by all slots, so they stay.
func reset() -> void:
	current_episode = &""
	completed_episodes.clear()
	flags.clear()
	scene_state = {}


func to_dict() -> Dictionary:
	var completed: Array[String] = []
	for id in completed_episodes:
		completed.append(String(id))
	var flag_data := {}
	for key in flags:
		flag_data[String(key)] = flags[key]
	return {
		"version": SAVE_VERSION,
		"meta": {"saved_at": int(Time.get_unix_time_from_system()), "preview": _preview_text()},
		"current_episode": String(current_episode),
		"completed_episodes": completed,
		"flags": flag_data,
		"scene": scene_state.duplicate(true),
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
	for line_key: Variant in data.get("seen_lines", []):  # v2 saves kept read lines per save.
		seen_lines[String(line_key)] = true


## Upgrade save data from older versions to SAVE_VERSION, one step at a time.
static func migrate(data: Dictionary) -> Dictionary:
	data = data.duplicate(true)
	var version := int(data.get("version", 1))  # JSON numbers load as float
	if version < 2:
		data["scene"] = {}
		data["seen_lines"] = []
		version = 2
	if version < 3:
		data["meta"] = {"saved_at": 0, "preview": ""}  # from_dict still merges seen_lines.
		version = 3
	data["version"] = version
	return data


## Text of the line the player is on, for the slot list.
func _preview_text() -> String:
	var story: Dictionary = scene_state.get("story", {})
	var history: Array = story.get("history", [])
	if history.is_empty():
		return ""
	var entry: Dictionary = history[-1]
	var text := _bbcode.sub(String(entry.get("text", "")), "", true)
	var speaker := String(entry.get("speaker", ""))
	return ("%s: %s" % [speaker, text]) if not speaker.is_empty() else text


#region Slots

## Slot ids in display order: the autosave slot, then "1" to SLOT_COUNT.
func slot_ids() -> Array[String]:
	var ids: Array[String] = [AUTO_SLOT]
	for i in SLOT_COUNT:
		ids.append(str(i + 1))
	return ids


func slot_path(slot: String) -> String:
	return save_dir.path_join("slot_%s.json" % slot)


func has_slot(slot: String) -> bool:
	return has_save(slot_path(slot))


func save_slot(slot: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK:
		return err
	err = save_game(slot_path(slot))
	if err == OK:
		save_system()
	return err


func load_slot(slot: String) -> Error:
	return load_game(slot_path(slot))


func delete_slot(slot: String) -> void:
	delete_save(slot_path(slot))


## Summary of a slot for the slot list, or {} when it's empty or unreadable:
## {"saved_at": unix time, "episode": episode id, "in_episode": saved mid-episode,
##  "preview": text of the saved line}.
func slot_info(slot: String) -> Dictionary:
	var path := slot_path(slot)
	var data := _read_json(path)
	if data.is_empty():
		return {}
	data = migrate(data)
	var meta: Dictionary = data.get("meta", {})
	var saved_at := int(meta.get("saved_at", 0))
	if saved_at <= 0:
		saved_at = FileAccess.get_modified_time(path)  # Saves from before v3 have no time.
	var scene: Dictionary = data.get("scene", {})
	return {
		"saved_at": saved_at,
		"episode": String(data.get("current_episode", "")),
		"in_episode": not scene.is_empty(),
		"preview": String(meta.get("preview", "")),
	}


## The most recently written slot, or "" when there are no saves.
func latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot in slot_ids():
		var info := slot_info(slot)
		if not info.is_empty() and int(info["saved_at"]) > best_time:
			best = slot
			best_time = int(info["saved_at"])
	return best


## Scene to open after loading: the saved episode's entry scene, or "" when the save is
## between episodes (stay on the title screen).
func loaded_scene_path() -> String:
	var episode := get_episode(StringName(scene_state.get("episode", "")))
	return episode.entry_scene if episode and episode.is_playable() else ""


## Moves the single save from before slots existed into slot 1, once.
func migrate_legacy_save(legacy_path: String = LEGACY_SAVE_PATH) -> void:
	if not has_save(legacy_path) or has_slot("1"):
		return
	var data := _read_json(legacy_path)
	if data.is_empty():
		return
	for line_key: Variant in data.get("seen_lines", []):
		seen_lines[String(line_key)] = true
	if DirAccess.make_dir_recursive_absolute(save_dir) != OK:
		return
	if _write_json(slot_path("1"), data) == OK:
		save_system()
		delete_save(legacy_path)

#endregion


#region Files

func has_save(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


func save_game(path: String) -> Error:
	return _write_json(path, to_dict())


## Loads `path`, falling back to its .bak if the main file is missing or unreadable.
func load_game(path: String) -> Error:
	if not has_save(path):
		return ERR_FILE_NOT_FOUND
	var data := _read_json(path)
	if data.is_empty():
		return ERR_PARSE_ERROR
	if int(data.get("version", 1)) > SAVE_VERSION:
		return ERR_FILE_UNRECOGNIZED  # Made by a newer build of the game.
	from_dict(data)
	return OK


func delete_save(path: String) -> void:
	for candidate: String in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


## Writes data shared by all slots (read lines).
func save_system() -> Error:
	return _write_json(system_path, {"version": SYSTEM_VERSION, "seen_lines": seen_lines.keys()})


## Adds the read lines from the system file to the ones already known.
func load_system() -> void:
	for line_key: Variant in _read_json(system_path).get("seen_lines", []):
		seen_lines[String(line_key)] = true


## Crash-safe write: write a temp file, keep the previous file as .bak, then rename.
func _write_json(path: String, data: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if not file.store_string(JSON.stringify(data, "\t")):
		file.close()
		return ERR_FILE_CANT_WRITE
	file.close()
	if FileAccess.file_exists(path):
		var backup_err := DirAccess.rename_absolute(path, path + ".bak")
		if backup_err != OK:
			return backup_err
	return DirAccess.rename_absolute(tmp, path)


## Reads a JSON object from `path`, or from its .bak if the main file is missing or broken.
## Returns {} when neither can be read.
func _read_json(path: String) -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if parsed is Dictionary:
			return parsed
	return {}

#endregion
