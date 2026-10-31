class_name StoryRunner
extends RefCounted
## Steps through a Dialogue Manager script one line at a time, with no UI.
## The VN player shows what it emits; tests drive it directly.
##
## It deliberately doesn't name autoloads (`GameState`, `DialogueManager`) in code, because
## headless test scripts compile before autoloads exist. The owner passes them in instead.

signal line_changed(line: DialogueLine)
signal ended

const HISTORY_LIMIT := 200

## Something with the GameState API (mark_line_seen / is_line_seen). Usually the GameState autoload.
var state: Node
## Extra state objects passed to Dialogue Manager for this conversation.
var extra_game_states: Array = []

var resource: DialogueResource
var line: DialogueLine
## Whether the current line had already been read before it was shown (for skip mode).
var line_was_seen: bool = false
## Recently shown lines, oldest first: [{"speaker": String, "text": String}].
var history: Array[Dictionary] = []

var _busy: bool = false


## True while waiting for Dialogue Manager (e.g. during an awaited mutation like a puzzle).
func is_busy() -> bool:
	return _busy


func has_choices() -> bool:
	return line != null and not line.responses.is_empty()


## Responses the player may pick (conditions passed).
func available_choices() -> Array[DialogueResponse]:
	var result: Array[DialogueResponse] = []
	if line == null:
		return result
	for response: DialogueResponse in line.responses:
		if response.is_allowed:
			result.append(response)
	return result


func start(dialogue: DialogueResource, cue: String = "start") -> void:
	resource = dialogue
	history.clear()
	await _go(cue)


## Continue to the next line. Ignored while busy or when the line is waiting for a choice.
func advance() -> void:
	if line == null or _busy or has_choices():
		return
	await _go(line.next_id)


func choose(response: DialogueResponse) -> void:
	if line == null or _busy or not response.is_allowed:
		return
	_push_history("", "> " + response.text)
	await _go(response.next_id)


## Everything needed to come back to exactly this line later.
func snapshot() -> Dictionary:
	if resource == null or line == null:
		return {}
	return {
		"dialogue": resource.resource_path,
		"line_id": line.id,
		"history": history.duplicate(true),
	}


## Restore a snapshot made by snapshot(). Falls back to the start cue if the saved line no
## longer exists (e.g. the script was edited since the save was made).
func resume(data: Dictionary) -> void:
	resource = load(String(data.get("dialogue", ""))) as DialogueResource
	if resource == null:
		push_error("StoryRunner: can't load dialogue %s" % data.get("dialogue", ""))
		ended.emit()
		return
	history.clear()
	for entry: Variant in data.get("history", []):
		if entry is Dictionary:
			history.append(entry)
	# The saved line is the last history entry; it gets re-added when shown again.
	if not history.is_empty():
		history.pop_back()
	var line_id := String(data.get("line_id", ""))
	if not _line_exists(line_id):
		push_warning("StoryRunner: saved line '%s' not found in %s, starting over" % [line_id, resource.resource_path])
		line_id = "start"
	await _go(line_id)


## Stable key for "has the player read this line" tracking.
func line_key(dialogue_line: DialogueLine) -> String:
	return "%s:%s" % [resource.resource_path, dialogue_line.id.split("|")[0]]


func _go(key: String) -> void:
	_busy = true
	var manager: Object = Engine.get_singleton("DialogueManager")
	var next: DialogueLine = await manager.get_next_dialogue_line(resource, key, extra_game_states)
	_busy = false
	line = next
	if line == null:
		ended.emit()
		return
	var seen_key := line_key(line)
	line_was_seen = state != null and state.is_line_seen(seen_key)
	if state != null:
		state.mark_line_seen(seen_key)
	_push_history(line.character, line.text)
	line_changed.emit(line)


func _push_history(speaker: String, text: String) -> void:
	history.append({"speaker": speaker, "text": text})
	while history.size() > HISTORY_LIMIT:
		history.pop_front()


func _line_exists(line_id: String) -> bool:
	if line_id.is_empty():
		return false
	var key: String = line_id.split("|")[0]
	if "@" in key:
		return true  # Points into another dialogue file; let Dialogue Manager resolve it.
	return resource.lines.has(key) or resource.cues.has(key)
