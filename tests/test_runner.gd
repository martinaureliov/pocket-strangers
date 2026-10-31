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
const TEST_SAVE := "user://test_save.json"

var passed := 0
var failed := 0


func _initialize() -> void:
	await process_frame  # Let autoloads enter the tree and run _ready.
	for method in get_method_list():
		var test_name: String = method.name
		if not test_name.begins_with("test_"):
			continue
		if await call(test_name) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % test_name)
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
	var state := GameStateScript.new()
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
	var state := GameStateScript.new()
	check(not state.has_flag(&"met_stranger"), "flag starts unset")
	check_eq(state.get_flag(&"met_stranger", false), false, "default returned")
	state.set_flag(&"met_stranger")
	check_eq(state.get_flag(&"met_stranger"), true, "flag set")
	state.free()
	return true


func test_save_round_trip() -> bool:
	var state := GameStateScript.new()
	state.delete_save(TEST_SAVE)
	state.current_episode = &"ep02"
	state.complete_episode(&"ep01")
	state.set_flag(&"trusted_stranger", true)
	state.set_flag(&"player_name", "Alex")
	state.mark_line_seen("res://x.dialogue:3")
	state.scene_state = {"episode": "ep02", "story": {"line_id": "7"}}
	check_eq(state.save_game(TEST_SAVE), OK, "save ok")

	var restored := GameStateScript.new()
	check_eq(restored.load_game(TEST_SAVE), OK, "load ok")
	check_eq(restored.current_episode, &"ep02", "current episode restored")
	check(restored.is_episode_completed(&"ep01"), "completed episode restored")
	check_eq(restored.get_flag(&"trusted_stranger"), true, "bool flag restored")
	check_eq(restored.get_flag(&"player_name"), "Alex", "string flag restored")
	check(restored.is_line_seen("res://x.dialogue:3"), "seen line restored")
	check_eq(restored.scene_state.get("story", {}).get("line_id"), "7", "scene position restored")

	state.delete_save(TEST_SAVE)
	state.free()
	restored.free()
	return true


func test_load_falls_back_to_backup() -> bool:
	var state := GameStateScript.new()
	state.delete_save(TEST_SAVE)
	state.set_flag(&"first", true)
	state.save_game(TEST_SAVE)
	state.set_flag(&"second", true)
	state.save_game(TEST_SAVE)  # Previous save becomes .bak
	check(FileAccess.file_exists(TEST_SAVE + ".bak"), "previous save kept as .bak")

	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)  # Simulate a corrupted save.
	file.store_string("{ not json")
	file.close()

	var restored := GameStateScript.new()
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
	var state := GameStateScript.new()
	state.from_dict(v1)
	check_eq(state.get_flag(&"a"), true, "v1 flags kept")
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
	return true


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
	check_eq(player.get_node("%QuickMenu").get_child_count(), 6, "quick menu built")
	player.queue_free()
	await process_frame
	return true
