extends SceneTree
## Headless GDScript test runner. Exits 0 when all tests pass, 1 otherwise.
##   godot --headless --path . --import            # once, on a fresh checkout
##   godot --headless --path . --script res://tests/test_runner.gd
##
## Each test is a method named `test_*` that returns `true` when it finishes.
## A test that hits a runtime error aborts and returns a default value, which is
## counted as a failure (bare `assert()` would hang the run instead).
##
## This script compiles before autoloads exist, so it never names `GameState` or
## `DialogueManager` directly: it looks them up on `root` at runtime.

const GameStateScript := preload("res://scripts/autoload/game_state.gd")
const EP01_DIALOGUE := "res://episodes/ep01/dialogue/ep01_placeholder.dialogue"
## Everything the tests write lives here, so the developer's real saves are never touched.
const TEST_DIR := "user://test_run"
const TEST_SAVE := TEST_DIR + "/test_save.json"
const TEST_SAVES := TEST_DIR + "/saves"
const TEST_SYSTEM := TEST_DIR + "/system.json"
const TEST_LEGACY := TEST_DIR + "/legacy_save.json"
const LOAD_SCREEN_SCENE := "res://scenes/ui/save_load_screen/save_load_screen.tscn"
const SETTINGS_SCREEN_SCENE := "res://scenes/ui/settings_screen/settings_screen.tscn"
## Safe to preload: the Settings script doesn't name any autoload.
const SettingsScript := preload("res://scripts/autoload/settings.gd")
const TEST_SETTINGS := TEST_DIR + "/settings.cfg"

var passed := 0
var failed := 0


func _initialize() -> void:
	await process_frame  # Let autoloads enter the tree and run _ready.
	# Point the real autoload at the test folder before any test can write a save.
	_reset_test_dir()
	var autoload_state := root.get_node_or_null("GameState")
	if autoload_state != null:
		autoload_state.save_dir = TEST_DIR + "/autoload_saves"
		autoload_state.system_path = TEST_DIR + "/autoload_system.json"
		autoload_state.clear_seen_lines()  # _ready loaded the developer's read lines.
	var autoload_settings := root.get_node_or_null("Settings")
	if autoload_settings != null:
		autoload_settings.path = TEST_SETTINGS
		autoload_settings.reset_to_defaults()  # _ready loaded the developer's settings.
	for method in get_method_list():
		var test_name: String = method.name
		if not test_name.begins_with("test_"):
			continue
		if await call(test_name) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % test_name)
	if autoload_settings != null:
		autoload_settings.reset_to_defaults()  # Leave the audio buses at their defaults.
	_remove_dir(TEST_DIR)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s" % label)


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])


# --- Helpers -----------------------------------------------------------------

## A GameState that is not in the tree and writes only into the test folder.
func _new_state() -> Node:
	var state := GameStateScript.new()
	state.save_dir = TEST_SAVES
	state.system_path = TEST_SYSTEM
	return state


## Deletes everything the tests wrote and recreates the empty test folder.
func _reset_test_dir() -> void:
	_remove_dir(TEST_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Rewrites the saved_at time of a slot file, to make "newest slot" deterministic.
func _set_saved_at(state: Node, slot: String, unix_time: int) -> void:
	var path: String = state.slot_path(slot)
	var data := _read_json(path)
	data["meta"]["saved_at"] = unix_time
	_write_text(path, JSON.stringify(data))


## A scene_state like the VN player writes, with the given lines in the story history.
func _scene_with_history(history: Array) -> Dictionary:
	return {"episode": "ep01", "story": {"line_id": "4", "history": history}, "stage": {}}

## Stands in for the VN player's `Stage` in dialogue scripts. Must implement every
## Stage.* call the scripts make: a missing method makes Dialogue Manager assert.
class FakeStage extends Node:
	var calls: Array[String] = []
	var puzzle_result: bool = true
	var game_state: Node

	func background(bg_name: String) -> void:
		calls.append("background:" + bg_name)

	func show_character(character: String, expression: String = "neutral", slot: String = "center", _pose: String = "default") -> void:
		calls.append("show:%s:%s:%s" % [character, expression, slot])

	func hide_character(character: String) -> void:
		calls.append("hide:" + character)

	func clear_characters() -> void:
		calls.append("clear")

	func puzzle(_scene_path: String, result_flag: String) -> bool:
		calls.append("puzzle:" + result_flag)
		game_state.set_flag(StringName(result_flag), puzzle_result)
		return puzzle_result


## Returns [game_state, stage] with a fresh GameState and a registered FakeStage,
## or an empty array if the autoloads aren't available.
func _story_setup() -> Array:
	var game_state := root.get_node_or_null("GameState")
	var manager := root.get_node_or_null("DialogueManager")
	check(game_state != null, "GameState autoload is available")
	check(manager != null, "DialogueManager autoload is available")
	if game_state == null or manager == null:
		return []
	game_state.reset()
	var stage := FakeStage.new()
	stage.game_state = game_state
	root.add_child(stage)
	manager.register_state_context("Stage", stage)
	return [game_state, stage]


func _story_teardown(stage: Node) -> void:
	root.get_node("DialogueManager").unregister_state_context("Stage")
	stage.queue_free()


func _new_runner(game_state: Node) -> StoryRunner:
	var runner := StoryRunner.new()
	runner.state = game_state
	return runner


## Plays the dialogue to the end, picking the first (or last) available choice each time.
## Returns true if the conversation ended within the step limit.
func _play_through(runner: StoryRunner, pick_last: bool) -> bool:
	var ended := [false]
	runner.ended.connect(func() -> void: ended[0] = true)
	await runner.start(load(EP01_DIALOGUE))
	var steps := 0
	while not ended[0] and steps < 200:
		steps += 1
		if runner.has_choices():
			var choices := runner.available_choices()
			await runner.choose(choices[-1] if pick_last else choices[0])
		else:
			await runner.advance()
	return ended[0]


# --- Episodes ----------------------------------------------------------------

func test_five_episodes_load_in_order() -> bool:
	var state := _new_state()
	var episodes: Array[Episode] = state.get_episodes()
	check_eq(episodes.size(), 5, "episode count")
	for i in episodes.size():
		check_eq(episodes[i].number, i + 1, "episode %d number" % (i + 1))
		check_eq(episodes[i].id, StringName("ep%02d" % (i + 1)), "episode %d id" % (i + 1))
	check(episodes[0].is_playable(), "episode 1 has an entry scene")
	state.free()
	return true


# --- GameState ---------------------------------------------------------------

func test_flags() -> bool:
	var state := _new_state()
	check(not state.has_flag(&"met_stranger"), "flag starts unset")
	check_eq(state.get_flag(&"met_stranger", false), false, "default returned")
	state.set_flag(&"met_stranger")
	check_eq(state.get_flag(&"met_stranger"), true, "flag set")
	state.free()
	return true


func test_save_round_trip() -> bool:
	_reset_test_dir()
	var state := _new_state()
	state.current_episode = &"ep02"
	state.complete_episode(&"ep01")
	state.set_flag(&"trusted_stranger", true)
	state.set_flag(&"player_name", "Alex")
	state.mark_line_seen("res://x.dialogue:3")
	state.scene_state = {"episode": "ep02", "story": {"line_id": "7"}}
	check_eq(state.save_game(TEST_SAVE), OK, "save ok")

	var restored := _new_state()
	check_eq(restored.load_game(TEST_SAVE), OK, "load ok")
	check_eq(restored.current_episode, &"ep02", "current episode restored")
	check(restored.is_episode_completed(&"ep01"), "completed episode restored")
	check_eq(restored.get_flag(&"trusted_stranger"), true, "bool flag restored")
	check_eq(restored.get_flag(&"player_name"), "Alex", "string flag restored")
	check(not restored.is_line_seen("res://x.dialogue:3"), "read lines are not stored in the save file")
	check(not _read_json(TEST_SAVE).has("seen_lines"), "save file has no seen_lines")
	check(_read_json(TEST_SAVE).has("meta"), "save file has meta")
	check_eq(_read_json(TEST_SAVE).get("version"), float(GameStateScript.SAVE_VERSION), "save file version")
	check_eq(restored.scene_state.get("story", {}).get("line_id"), "7", "scene position restored")

	state.delete_save(TEST_SAVE)
	state.free()
	restored.free()
	return true


func test_load_falls_back_to_backup() -> bool:
	_reset_test_dir()
	var state := _new_state()
	state.set_flag(&"first", true)
	state.save_game(TEST_SAVE)
	state.set_flag(&"second", true)
	state.save_game(TEST_SAVE)  # Previous save becomes .bak
	check(FileAccess.file_exists(TEST_SAVE + ".bak"), "previous save kept as .bak")

	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)  # Simulate a corrupted save.
	file.store_string("{ not json")
	file.close()

	var restored := _new_state()
	check_eq(restored.load_game(TEST_SAVE), OK, "loads from .bak")
	check(restored.has_flag(&"first"), "backup has the older flags")
	check(not restored.has_flag(&"second"), "backup is the previous save")

	state.delete_save(TEST_SAVE)
	state.free()
	restored.free()
	return true


func test_migrates_v1_save() -> bool:
	var v1 := {"version": 1.0, "current_episode": "ep01", "completed_episodes": [], "flags": {"a": true}}
	var migrated: Dictionary = GameStateScript.migrate(v1)
	check_eq(migrated.get("version"), GameStateScript.SAVE_VERSION, "version bumped")
	check_eq(migrated.get("scene"), {}, "scene added")
	check_eq(migrated.get("seen_lines"), [], "seen_lines added")
	check_eq(migrated.get("meta"), {"saved_at": 0, "preview": ""}, "meta added")
	var state := _new_state()
	state.from_dict(v1)
	check_eq(state.get_flag(&"a"), true, "v1 flags kept")
	state.free()
	return true


# --- Save slots ----------------------------------------------------------------

func test_slot_ids() -> bool:
	var state := _new_state()
	var ids: Array[String] = state.slot_ids()
	check_eq(ids.size(), GameStateScript.SLOT_COUNT + 1, "slot count")
	check_eq(ids[0], GameStateScript.AUTO_SLOT, "auto slot first")
	check_eq(ids[1], "1", "first manual slot")
	check_eq(ids[-1], str(GameStateScript.SLOT_COUNT), "last manual slot")
	check_eq(state.slot_path("3"), TEST_SAVES + "/slot_3.json", "slot path")
	state.free()
	return true


func test_slot_round_trip_and_info() -> bool:
	_reset_test_dir()
	var state := _new_state()
	state.current_episode = &"ep01"
	state.set_flag(&"met", true)
	state.scene_state = _scene_with_history([
		{"speaker": "", "text": "Earlier line."},
		{"speaker": "Stranger", "text": "[b]Hello[/b] there"},
	])
	check(not state.has_slot("2"), "slot starts empty")
	check_eq(state.save_slot("2"), OK, "save to slot 2")
	check(state.has_slot("2"), "slot 2 has a save")
	check(not state.has_slot("3"), "slot 3 still empty")

	var info: Dictionary = state.slot_info("2")
	check_eq(info.get("episode"), "ep01", "info episode")
	check_eq(info.get("in_episode"), true, "info in_episode")
	check_eq(info.get("preview"), "Stranger: Hello there", "preview is the last line, bbcode stripped")
	check(int(info.get("saved_at", 0)) > 1700000000, "info saved_at is a unix time")

	var restored := _new_state()
	check_eq(restored.load_slot("2"), OK, "load slot 2")
	check_eq(restored.current_episode, &"ep01", "episode restored from slot")
	check_eq(restored.get_flag(&"met"), true, "flag restored from slot")
	check_eq(restored.scene_state.get("story", {}).get("line_id"), "4", "position restored from slot")

	# Narration (no speaker) previews as plain text.
	state.scene_state = _scene_with_history([{"speaker": "", "text": "The bus is late."}])
	state.save_slot("2")
	check_eq(state.slot_info("2").get("preview"), "The bus is late.", "narration preview has no speaker")

	# Saved between episodes: no position, no preview.
	state.scene_state = {}
	state.complete_episode(&"ep01")
	state.save_slot("auto")
	var between: Dictionary = state.slot_info("auto")
	check_eq(between.get("in_episode"), false, "between episodes is not in_episode")
	check_eq(between.get("preview"), "", "no preview between episodes")

	state.delete_slot("2")
	check(not state.has_slot("2"), "slot deleted")
	check_eq(state.slot_info("2"), {}, "deleted slot has no info")
	state.free()
	restored.free()
	return true


func test_empty_slot_info_and_latest_slot() -> bool:
	_reset_test_dir()
	var state := _new_state()
	check_eq(state.slot_info("5"), {}, "empty slot info is {}")
	check_eq(state.load_slot("5"), ERR_FILE_NOT_FOUND, "loading an empty slot fails")
	check_eq(state.latest_slot(), "", "no saves, no latest slot")
	state.free()
	return true


func test_latest_slot_is_newest() -> bool:
	_reset_test_dir()
	var state := _new_state()
	for slot: String in ["1", "2", "auto"]:
		check_eq(state.save_slot(slot), OK, "save slot %s" % slot)
	_set_saved_at(state, "1", 1000)
	_set_saved_at(state, "2", 3000)
	_set_saved_at(state, "auto", 2000)
	check_eq(state.slot_info("1").get("saved_at"), 1000, "saved_at read from meta")
	check_eq(state.latest_slot(), "2", "slot 2 is newest")
	_set_saved_at(state, "1", 5000)
	check_eq(state.latest_slot(), "1", "slot 1 is newest after its time changes")
	state.delete_slot("1")
	check_eq(state.latest_slot(), "2", "deleted slot is skipped")
	state.free()
	return true


func test_newer_save_version_refused() -> bool:
	_reset_test_dir()
	var state := _new_state()
	state.set_flag(&"keep_me", true)
	var future := {"version": GameStateScript.SAVE_VERSION + 1, "current_episode": "ep03", "flags": {"from_future": true}}
	_write_text(state.slot_path("4"), JSON.stringify(future))
	check_eq(state.load_slot("4"), ERR_FILE_UNRECOGNIZED, "newer version refused")
	check_eq(state.current_episode, &"", "state untouched by refused load")
	check(state.has_flag(&"keep_me") and not state.has_flag(&"from_future"), "flags untouched by refused load")
	state.free()
	return true


func test_legacy_save_migrates_to_slot_1() -> bool:
	_reset_test_dir()
	var legacy := {
		"version": 2,
		"current_episode": "ep01",
		"completed_episodes": [],
		"flags": {"from_legacy": true},
		"scene": _scene_with_history([{"speaker": "Stranger", "text": "Old save."}]),
		"seen_lines": ["res://legacy.dialogue:1", "res://legacy.dialogue:2"],
	}
	_write_text(TEST_LEGACY, JSON.stringify(legacy))
	var state := _new_state()
	state.migrate_legacy_save(TEST_LEGACY)
	check(state.has_slot("1"), "legacy save moved into slot 1")
	check(not state.has_save(TEST_LEGACY), "legacy file removed")
	check(state.is_line_seen("res://legacy.dialogue:2"), "legacy read lines merged")
	var info: Dictionary = state.slot_info("1")
	check_eq(info.get("episode"), "ep01", "migrated slot episode")
	check_eq(info.get("in_episode"), true, "migrated slot keeps its position")
	check(int(info.get("saved_at", 0)) > 0, "migrated slot gets a time (file time)")
	var restored := _new_state()
	check_eq(restored.load_slot("1"), OK, "migrated slot loads")
	check_eq(restored.get_flag(&"from_legacy"), true, "migrated slot keeps flags")
	restored.load_system()
	check(restored.is_line_seen("res://legacy.dialogue:1"), "legacy read lines reached the system file")

	# Slot 1 is taken now: a second legacy save must stay where it is.
	var second := {"version": 2, "current_episode": "ep02", "flags": {"second": true}, "seen_lines": ["res://second.dialogue:1"]}
	_write_text(TEST_LEGACY, JSON.stringify(second))
	var other := _new_state()
	other.migrate_legacy_save(TEST_LEGACY)
	check(other.has_save(TEST_LEGACY), "legacy file kept when slot 1 is used")
	check(not other.is_line_seen("res://second.dialogue:1"), "no read lines merged when slot 1 is used")
	check_eq(other.slot_info("1").get("episode"), "ep01", "slot 1 not overwritten")

	# No legacy file at all: nothing happens.
	_reset_test_dir()
	var empty := _new_state()
	empty.migrate_legacy_save(TEST_LEGACY)
	check(not empty.has_slot("1"), "nothing to migrate")
	state.free()
	restored.free()
	other.free()
	empty.free()
	return true


func test_seen_lines_are_global() -> bool:
	_reset_test_dir()
	var state := _new_state()
	state.mark_line_seen("res://a.dialogue:1")
	state.reset()
	check(state.is_line_seen("res://a.dialogue:1"), "reset keeps read lines")
	state.from_dict({"version": 3, "flags": {"x": true}})
	check(state.is_line_seen("res://a.dialogue:1"), "from_dict keeps read lines")
	check(not state.to_dict().has("seen_lines"), "to_dict has no seen_lines")

	check_eq(state.save_slot("1"), OK, "save slot 1")
	state.clear_seen_lines()
	check(not state.is_line_seen("res://a.dialogue:1"), "clear_seen_lines clears")
	state.load_slot("1")
	check(not state.is_line_seen("res://a.dialogue:1"), "loading a slot does not bring read lines back")
	state.load_system()  # save_slot wrote the system file.
	check(state.is_line_seen("res://a.dialogue:1"), "load_system restores read lines")

	state.mark_line_seen("res://b.dialogue:2")
	check_eq(state.save_system(), OK, "save_system ok")
	var other := _new_state()
	other.mark_line_seen("res://c.dialogue:3")
	other.load_system()
	check(other.is_line_seen("res://a.dialogue:1") and other.is_line_seen("res://b.dialogue:2"), "system file round trip")
	check(other.is_line_seen("res://c.dialogue:3"), "load_system merges into known lines")

	# Old v2 slots carried their own read lines: from_dict still merges them.
	var v2 := _new_state()
	v2.from_dict({"version": 2, "seen_lines": ["res://old.dialogue:9"]})
	check(v2.is_line_seen("res://old.dialogue:9"), "v2 save's read lines merged")
	state.free()
	other.free()
	v2.free()
	return true


func test_loaded_scene_path() -> bool:
	var state := _new_state()
	state.scene_state = {"episode": "ep01", "story": {}}
	check_eq(state.loaded_scene_path(), "res://episodes/ep01/ep01.tscn", "ep01 save opens the episode scene")
	state.scene_state = {}
	check_eq(state.loaded_scene_path(), "", "between episodes stays on the title")
	state.scene_state = {"episode": "ep02"}
	check_eq(state.loaded_scene_path(), "", "episode without an entry scene stays on the title")
	state.scene_state = {"episode": "nope"}
	check_eq(state.loaded_scene_path(), "", "unknown episode stays on the title")
	state.free()
	return true


# --- Puzzles -----------------------------------------------------------------

func test_combination_lock_rules() -> bool:
	var lock := CombinationLock.new([3, 1, 4])
	check_eq(lock.dial_count(), 3, "three dials")
	check_eq(lock.digits, [0, 0, 0] as Array[int], "dials start at zero")
	lock.rotate(0, -1)
	check_eq(lock.digits[0], 9, "0 turns down to 9")
	lock.rotate(0, 1)
	check_eq(lock.digits[0], 0, "9 turns up to 0")
	check(not lock.try_open(), "wrong code stays locked")
	lock.rotate(0, 3)
	lock.rotate(1, 1)
	lock.rotate(2, 4)
	check(lock.try_open(), "right code opens")
	check_eq(lock.attempts, 2, "attempts counted")
	lock.rotate(5, 1)  # Out of range: ignored.
	check(lock.is_open(), "out-of-range dial ignored")
	return true


# --- Dialogue ----------------------------------------------------------------

func test_dialogue_file_compiles() -> bool:
	var dialogue := load("res://tests/fixtures/smoke.dialogue") as DialogueResource
	check(dialogue != null, "smoke.dialogue loads as a DialogueResource")
	if dialogue == null:
		return true
	check(dialogue.get_cues().has("start"), "has the 'start' cue")
	check(dialogue.character_names.has("Stranger"), "knows the 'Stranger' character")
	return true


func test_episode1_claim_and_solve() -> bool:
	var setup := _story_setup()
	if setup.is_empty():
		return true
	var game_state: Node = setup[0]
	var stage: FakeStage = setup[1]
	stage.puzzle_result = true

	var runner := _new_runner(game_state)
	check(await _play_through(runner, false), "episode 1 reaches the end (first choices)")
	check_eq(game_state.get_flag(&"ep01_claimed_phone"), true, "choice set claimed flag")
	check_eq(game_state.get_flag(&"ep01_phone_unlocked"), true, "puzzle result stored")
	check(stage.calls.has("background:bus_stop_night"), "background shown")
	check(stage.calls.has("show:stranger:smile:right"), "expression changed after choice")
	check(stage.calls.has("puzzle:ep01_phone_unlocked"), "puzzle ran")
	var texts := runner.history.map(func(e: Dictionary) -> String: return e.text)
	check(texts.has("So it really is yours. What does it say?"), "line reacts to the earlier choice")
	_story_teardown(stage)
	return true


func test_episode1_deny_and_fail() -> bool:
	var setup := _story_setup()
	if setup.is_empty():
		return true
	var game_state: Node = setup[0]
	var stage: FakeStage = setup[1]
	stage.puzzle_result = false

	var runner := _new_runner(game_state)
	check(await _play_through(runner, true), "episode 1 reaches the end (last choices)")
	check_eq(game_state.get_flag(&"ep01_claimed_phone"), false, "choice set claimed flag to false")
	check_eq(game_state.get_flag(&"ep01_phone_unlocked"), false, "failed puzzle stored")
	var texts := runner.history.map(func(e: Dictionary) -> String: return e.text)
	check(texts.has("The phone stays dark."), "failed-puzzle branch taken")
	_story_teardown(stage)
	return true


func test_resume_at_exact_line() -> bool:
	var setup := _story_setup()
	if setup.is_empty():
		return true
	var game_state: Node = setup[0]
	var stage: FakeStage = setup[1]

	var runner := _new_runner(game_state)
	await runner.start(load(EP01_DIALOGUE))
	var steps := 0
	while runner.line != null and not runner.has_choices() and steps < 50:
		steps += 1
		await runner.advance()
	check(runner.has_choices(), "reached the first choice")
	var saved := runner.snapshot()
	var saved_text: String = runner.line.text
	var saved_history_size := runner.history.size()

	var resumed := _new_runner(game_state)
	await resumed.resume(JSON.parse_string(JSON.stringify(saved)))  # Through JSON, like a real save.
	check(resumed.line != null, "resumed to a line")
	if resumed.line != null:
		check_eq(resumed.line.id, runner.line.id, "same line id")
		check_eq(resumed.line.text, saved_text, "same line text")
		check_eq(resumed.available_choices().size(), runner.available_choices().size(), "same choices")
		check(resumed.line_was_seen, "line counts as already read")
	check_eq(resumed.history.size(), saved_history_size, "history restored without duplicates")

	var missing := saved.duplicate()
	missing["line_id"] = "99999"
	var fallback := _new_runner(game_state)
	await fallback.resume(missing)
	check(fallback.line != null, "unknown saved line falls back to the start")
	_story_teardown(stage)
	return true


# --- Scenes (load and run the real UI, headless) ------------------------------

func test_scenes_load() -> bool:
	for path: String in [
		"res://scenes/main/main.tscn",
		"res://scenes/vn/vn_player.tscn",
		"res://episodes/ep01/ep01.tscn",
		"res://scenes/puzzles/combination_lock/combination_lock_puzzle.tscn",
	]:
		check(load(path) is PackedScene, "%s loads" % path)
	# A scene still loads when its script has a parse error, so compile every script explicitly.
	for dir: String in ["res://scenes", "res://scripts", "res://episodes"]:
		for path: String in _find_files(dir, ".gd"):
			var script := load(path) as Script
			check(script != null and script.can_instantiate(), "%s compiles" % path)
	return true


func _find_files(dir_path: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(extension):
			result.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		result.append_array(_find_files(dir_path.path_join(sub), extension))
	return result


func test_puzzle_scene_builds_and_finishes() -> bool:
	var puzzle := (load("res://scenes/puzzles/combination_lock/combination_lock_puzzle.tscn") as PackedScene).instantiate() as Puzzle
	check(puzzle != null, "lock scene is a Puzzle")
	if puzzle == null:
		return true
	var results: Array[bool] = []
	puzzle.finished.connect(func(solved: bool) -> void: results.append(solved))
	root.add_child(puzzle)
	await process_frame
	check(puzzle.get_child_count() > 0, "lock UI built")
	puzzle.finish(false)
	puzzle.finish(true)  # Second call ignored.
	check_eq(results, [false] as Array[bool], "finished emitted once")
	puzzle.queue_free()
	await process_frame
	return true


func test_episode1_scene_shows_first_line() -> bool:
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		check(false, "GameState autoload is available")
		return true
	game_state.reset()
	var player := (load("res://episodes/ep01/ep01.tscn") as PackedScene).instantiate()
	root.add_child(player)
	var frames := 0
	while player.runner.line == null and frames < 120:
		frames += 1
		await process_frame
	check(player.runner.line != null, "VN player shows a line")
	if player.runner.line != null:
		check_eq(player.runner.line.text, "It's late. The last bus is twenty minutes away.", "first line of episode 1")
	check_eq(game_state.current_episode, &"ep01", "episode started")
	check_eq(player.get_node("%Background").get_child_count(), 1, "background placeholder drawn")
	check(player.get_node("%DialogueBox").visible, "dialogue box visible")
	var quick_menu := player.get_node("%QuickMenu")
	check_eq(quick_menu.get_child_count(), 7, "quick menu built")
	var menu_labels: Array[String] = []
	for button: Button in quick_menu.get_children():
		menu_labels.append(button.text)
	check(menu_labels.has("Settings"), "quick menu has a Settings button")
	var settings := root.get_node_or_null("Settings")
	check(settings != null, "Settings autoload is available")
	if settings != null:
		var label := player.get_node("%DialogueLabel")
		check(is_equal_approx(label.seconds_per_step, settings.seconds_per_char()), "typing speed follows the text speed setting")
		settings.set_value(&"text_speed", 1.0)
		check_eq(label.seconds_per_step, 0.0, "max text speed types instantly")
		settings.reset_to_defaults()
		check(is_equal_approx(label.seconds_per_step, settings.seconds_per_char()), "typing speed follows a reset")
	player.queue_free()
	await process_frame
	return true

## Counts disabled buttons among the given buttons.
func _disabled_count(buttons: Array) -> int:
	var count := 0
	for button: Button in buttons:
		if button.disabled:
			count += 1
	return count


func test_save_load_screen_modes() -> bool:
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		check(false, "GameState autoload is available")
		return true
	_reset_test_dir()
	game_state.reset()
	game_state.scene_state = _scene_with_history([{"speaker": "Stranger", "text": "Hi."}])
	check_eq(game_state.save_slot("2"), OK, "slot 2 saved for the screen")
	game_state.reset()

	# Never name SaveLoadScreen here: it uses GameState, which doesn't exist when this script compiles.
	var screen := (load(LOAD_SCREEN_SCENE) as PackedScene).instantiate()
	check(screen != null and screen.has_signal("slot_chosen"), "save/load screen scene is a SaveLoadScreen")
	if screen == null:
		return true
	var modes: Dictionary = screen.get_script().Mode
	root.add_child(screen)
	await process_frame
	var slot_count: int = game_state.slot_ids().size()
	var chosen: Array[String] = []
	screen.slot_chosen.connect(func(slot: String) -> void: chosen.append(slot))

	screen.open(modes.LOAD)
	var buttons: Array = screen._grid.get_children()
	check(screen.visible, "screen shown in load mode")
	check_eq(buttons.size(), slot_count, "load mode: one button per slot")
	check_eq(_disabled_count(buttons), slot_count - 1, "load mode: only the used slot is enabled")
	check(not buttons[2].disabled, "load mode: slot 2 enabled")
	check(buttons[0].disabled and buttons[1].disabled, "load mode: empty auto and slot 1 disabled")
	check(buttons[2].text.contains("Stranger: Hi."), "load mode: slot shows the preview")
	buttons[2].pressed.emit()
	check_eq(chosen, ["2"] as Array[String], "load mode: pressing a slot emits slot_chosen")

	screen.open(modes.SAVE)
	await process_frame  # Old buttons are freed on the next frame.
	buttons = screen._grid.get_children()
	check_eq(buttons.size(), slot_count, "save mode: one button per slot")
	check_eq(_disabled_count(buttons), 1, "save mode: only the auto slot is disabled")
	check(buttons[0].disabled, "save mode: auto slot disabled")
	check(not buttons[1].disabled, "save mode: empty slot enabled")
	chosen.clear()
	buttons[1].pressed.emit()
	check_eq(chosen, ["1"] as Array[String], "save mode: empty slot saves right away")
	chosen.clear()
	buttons[2].pressed.emit()
	check(chosen.is_empty(), "save mode: used slot asks before saving")

	screen.queue_free()
	await process_frame
	_reset_test_dir()
	return true


func test_episode1_save_to_slot() -> bool:
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		check(false, "GameState autoload is available")
		return true
	_reset_test_dir()
	game_state.reset()
	var player := (load("res://episodes/ep01/ep01.tscn") as PackedScene).instantiate()
	root.add_child(player)
	var frames := 0
	while not player.can_save() and frames < 120:
		frames += 1
		await process_frame
	check(player.can_save(), "player can save once the first line shows")
	if not player.can_save():
		player.queue_free()
		return true
	check_eq(player.save_game("1"), OK, "save_game(\"1\") ok")
	check(game_state.has_slot("1"), "slot 1 written")
	var info: Dictionary = game_state.slot_info("1")
	check_eq(info.get("preview"), "It's late. The last bus is twenty minutes away.", "preview is the first line")
	check_eq(info.get("episode"), "ep01", "slot episode")
	check_eq(info.get("in_episode"), true, "slot is mid-episode")
	check_eq(game_state.latest_slot(), "1", "slot 1 is the latest")

	game_state.reset()
	check_eq(game_state.load_slot("1"), OK, "slot 1 loads")
	check_eq(game_state.loaded_scene_path(), "res://episodes/ep01/ep01.tscn", "loaded save opens ep01")
	player.queue_free()
	await process_frame
	game_state.reset()
	_reset_test_dir()
	return true


func test_title_screen_has_settings_button() -> bool:
	var title := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await process_frame
	var list := title.get_node_or_null("%EpisodeList")
	check(list != null, "title has an episode list")
	if list != null and list.get_child_count() > 0:
		var last := list.get_child(list.get_child_count() - 1) as Button
		check(last != null and last.text == "Settings", "title episode list ends with a Settings button")
	else:
		check(false, "title episode list has children")
	title.queue_free()
	await process_frame
	return true


# --- Settings -----------------------------------------------------------------

## A Settings that is not in the tree and stores its file in the test folder.
func _new_settings(file_name: String = "settings_fresh.cfg") -> Node:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var settings := SettingsScript.new()
	settings.path = TEST_DIR.path_join(file_name)
	return settings


func _bus_db(bus_name: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))


func _approx(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= tolerance


## True when a settings control (slider or toggle) shows the given setting value.
func _control_matches(control: Control, value: Variant) -> bool:
	if control is Range:
		return _approx((control as Range).value, float(value), 0.01)
	if control is BaseButton:
		return (control as BaseButton).button_pressed == value
	return false


func test_settings_defaults() -> bool:
	var settings := _new_settings()
	var defaults: Dictionary = SettingsScript.DEFAULTS
	check(defaults.size() > 0, "settings have defaults")
	for key: StringName in defaults:
		check_eq(settings.get_value(key), defaults[key], "default %s" % key)
	check_eq(settings.get_value(&"no_such_setting"), null, "unknown key reads as null")
	settings.free()
	return true


func test_settings_clamp_and_ignore_bad_values() -> bool:
	var settings := _new_settings()
	var changes: Array[StringName] = []
	settings.changed.connect(func(key: StringName) -> void: changes.append(key))
	settings.set_value(&"music_volume", 1.5)
	check_eq(settings.get_value(&"music_volume"), 1.0, "volume clamped to 1")
	settings.set_value(&"music_volume", -0.5)
	check_eq(settings.get_value(&"music_volume"), 0.0, "volume clamped to 0")
	settings.set_value(&"text_speed", 3)
	check_eq(settings.get_value(&"text_speed"), 1.0, "int value accepted and clamped")
	check(settings.get_value(&"text_speed") is float, "int value stored as float")
	check_eq(changes.size(), 3, "changed emitted for each accepted change")
	changes.clear()
	settings.set_value(&"no_such_setting", 1.0)
	settings.set_value(&"fullscreen", "yes")
	settings.set_value(&"sfx_volume", "loud")
	settings.set_value(&"text_speed", true)
	check_eq(settings.get_value(&"fullscreen"), false, "wrong type ignored for bool")
	check_eq(settings.get_value(&"sfx_volume"), 0.8, "wrong type ignored for float")
	check_eq(settings.get_value(&"text_speed"), 1.0, "bool does not replace a float")
	check(changes.is_empty(), "ignored values emit nothing")
	check_eq(settings.get_value(&"no_such_setting"), null, "unknown key not stored")
	settings.reset_to_defaults()
	settings.free()
	root.get_node("Settings").reset_to_defaults()  # The instance above changed the shared buses.
	return true


func test_settings_speed_curves() -> bool:
	var settings := _new_settings()
	settings.set_value(&"text_speed", 0.0)
	check(_approx(settings.seconds_per_char(), 0.08, 0.0001), "slowest typing is 0.08s per character")
	settings.set_value(&"text_speed", 0.5)
	check(_approx(settings.seconds_per_char(), 0.02, 0.0005), "middle typing speed is about 0.02s")
	settings.set_value(&"text_speed", 0.999)
	check(settings.seconds_per_char() > 0.0, "just under max is still typed")
	settings.set_value(&"text_speed", 1.0)
	check_eq(settings.seconds_per_char(), 0.0, "max text speed is instant")
	var previous := INF
	for i in 11:
		settings.set_value(&"text_speed", i / 10.0)
		var seconds: float = settings.seconds_per_char()
		check(seconds < previous, "typing delay shrinks as text speed rises (%d)" % i)
		previous = seconds

	settings.set_value(&"auto_speed", 0.0)
	check(_approx(settings.auto_delay_scale(), 2.0, 0.0001), "slowest auto delay scale is 2")
	settings.set_value(&"auto_speed", 0.5)
	check(_approx(settings.auto_delay_scale(), 1.0, 0.0001), "middle auto delay scale is 1")
	settings.set_value(&"auto_speed", 1.0)
	check(_approx(settings.auto_delay_scale(), 0.5, 0.0001), "fastest auto delay scale is 0.5")
	previous = INF
	for i in 11:
		settings.set_value(&"auto_speed", i / 10.0)
		var scale: float = settings.auto_delay_scale()
		check(scale < previous, "auto delay shrinks as auto speed rises (%d)" % i)
		previous = scale
	settings.free()
	return true


func test_settings_save_and_load_round_trip() -> bool:
	_reset_test_dir()
	var settings := _new_settings("round_trip.cfg")
	settings.set_value(&"text_speed", 0.25)
	settings.set_value(&"auto_speed", 0.75)
	settings.set_value(&"master_volume", 0.4)
	settings.set_value(&"music_volume", 0.3)
	settings.set_value(&"sfx_volume", 0.2)
	settings.set_value(&"voice_volume", 0.1)
	settings.set_value(&"fullscreen", true)
	check_eq(settings.save(), OK, "settings save")
	check(FileAccess.file_exists(settings.path), "settings file written")

	var loaded := _new_settings("round_trip.cfg")
	loaded.load_settings()
	for key: StringName in SettingsScript.DEFAULTS:
		check_eq(loaded.get_value(key), settings.get_value(key), "round trip %s" % key)
	check_eq(loaded.get_value(&"fullscreen"), true, "bool survives the round trip")
	settings.free()
	loaded.free()
	root.get_node("Settings").reset_to_defaults()  # The instances above changed the shared buses.
	return true


func test_settings_missing_or_corrupt_file_gives_defaults() -> bool:
	_reset_test_dir()
	var missing := _new_settings("does_not_exist.cfg")
	missing.set_value(&"text_speed", 0.1)
	missing.load_settings()
	check_eq(missing.get_value(&"text_speed"), 0.5, "missing file: defaults")
	missing.free()

	_write_text(TEST_DIR.path_join("corrupt.cfg"), "this is [not a valid\nconfig = = file")
	var corrupt := _new_settings("corrupt.cfg")
	corrupt.set_value(&"music_volume", 0.1)
	corrupt.load_settings()
	for key: StringName in SettingsScript.DEFAULTS:
		check_eq(corrupt.get_value(key), SettingsScript.DEFAULTS[key], "corrupt file: default %s" % key)
	corrupt.free()

	# Partial content: unknown keys and wrong types are skipped, valid keys are kept.
	_write_text(TEST_DIR.path_join("partial.cfg"), "[settings]\nmusic_volume=0.3\nsfx_volume=\"loud\"\nbogus=1\n")
	var partial := _new_settings("partial.cfg")
	partial.load_settings()
	check(_approx(partial.get_value(&"music_volume"), 0.3, 0.0001), "partial file: valid key loaded")
	check_eq(partial.get_value(&"sfx_volume"), 0.8, "partial file: wrong type falls back to the default")
	check_eq(partial.get_value(&"bogus"), null, "partial file: unknown key ignored")
	partial.free()
	root.get_node("Settings").reset_to_defaults()
	return true


func test_settings_volumes_reach_audio_buses() -> bool:
	var settings := _new_settings()
	for key: StringName in SettingsScript.VOLUME_BUSES:
		var bus_name: String = SettingsScript.VOLUME_BUSES[key]
		var bus := AudioServer.get_bus_index(bus_name)
		check(bus >= 0, "audio bus %s exists" % bus_name)
		if bus < 0:
			continue
		settings.set_value(key, 0.5)
		check(_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)), "%s sets bus %s volume" % [key, bus_name])
		check(not AudioServer.is_bus_mute(bus), "bus %s not muted at 0.5" % bus_name)
		settings.set_value(key, 0.0)
		check(AudioServer.is_bus_mute(bus), "bus %s muted at 0" % bus_name)
		settings.set_value(key, 0.25)
		check(not AudioServer.is_bus_mute(bus), "bus %s unmuted again" % bus_name)
		check(_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25)), "bus %s volume after unmute" % bus_name)
	settings.reset_to_defaults()
	check(_approx(_bus_db("Music"), linear_to_db(0.8)), "reset restores the Music bus")
	settings.free()
	return true


func test_bus_layout_has_expected_buses() -> bool:
	for bus_name: String in ["Master", "Music", "SFX", "Ambience", "Voice"]:
		check(AudioServer.get_bus_index(bus_name) >= 0, "bus %s exists" % bus_name)
	var ambience := AudioServer.get_bus_index("Ambience")
	if ambience >= 0:
		check_eq(AudioServer.get_bus_send(ambience), &"SFX", "Ambience sends to SFX")
	return true


func test_settings_screen() -> bool:
	var settings := root.get_node_or_null("Settings")
	check(settings != null, "Settings autoload is available")
	if settings == null:
		return true
	_reset_test_dir()
	settings.reset_to_defaults()
	var screen := (load(SETTINGS_SCREEN_SCENE) as PackedScene).instantiate()
	check(screen != null and screen.has_signal("closed"), "settings screen scene is a SettingsScreen")
	if screen == null:
		return true
	root.add_child(screen)
	await process_frame
	var closed: Array[bool] = []
	screen.closed.connect(func() -> void: closed.append(true))
	screen.open()
	check(screen.visible, "settings screen shown")

	var controls: Dictionary = screen.controls
	var defaults: Dictionary = SettingsScript.DEFAULTS
	for key: StringName in defaults:
		check(controls.has(key), "control for %s" % key)
		if controls.has(key):
			check(_control_matches(controls[key], settings.get_value(key)), "control for %s shows the setting" % key)

	# Moving a slider changes the setting at once.
	var slider := controls.get(&"text_speed") as Range
	check(slider != null, "text_speed control is a Range")
	if slider != null:
		slider.value = 0.9
		check(_approx(settings.get_value(&"text_speed"), slider.value, 0.0001), "slider change reaches Settings")
		check(settings.get_value(&"text_speed") > 0.8, "slider change is not lost")
	var music := controls.get(&"music_volume") as Range
	if music != null:
		music.value = 0.3
		check(_approx(settings.get_value(&"music_volume"), music.value, 0.0001), "music slider change reaches Settings")
		check(_approx(_bus_db("Music"), linear_to_db(maxf(music.value, 0.0001))), "music slider reaches the bus")
	var fullscreen := controls.get(&"fullscreen") as BaseButton
	check(fullscreen != null, "fullscreen control is a button")
	if fullscreen != null:
		fullscreen.button_pressed = true
		check_eq(settings.get_value(&"fullscreen"), true, "checkbox change reaches Settings")

	# Defaults button restores everything, in Settings and in the controls.
	var defaults_button := screen.find_child("DefaultsButton", true, false) as BaseButton
	check(defaults_button != null, "DefaultsButton exists")
	check(screen.find_child("BackButton", true, false) is BaseButton, "BackButton exists")
	if defaults_button != null:
		defaults_button.pressed.emit()
		for key: StringName in defaults:
			check_eq(settings.get_value(key), defaults[key], "defaults button resets %s" % key)
			if controls.has(key):
				check(_control_matches(controls[key], defaults[key]), "defaults button resets the %s control" % key)

	# close() saves to the (redirected) settings path and emits closed.
	check(settings.path.begins_with(TEST_DIR), "settings were redirected to the test folder")
	DirAccess.remove_absolute(settings.path)
	check(not FileAccess.file_exists(settings.path), "settings file removed before close")
	if slider != null:
		slider.value = 0.6
	screen.close()
	check(FileAccess.file_exists(settings.path), "close() writes the settings file")
	check_eq(closed.size(), 1, "close() emits closed once")
	var saved := ConfigFile.new()
	check_eq(saved.load(settings.path), OK, "saved settings file parses")
	if slider != null:
		check(_approx(float(saved.get_value(SettingsScript.SECTION, "text_speed", -1.0)), 0.6, 0.0001), "saved file holds the last slider value")

	screen.queue_free()
	await process_frame
	settings.reset_to_defaults()
	_reset_test_dir()
	return true
