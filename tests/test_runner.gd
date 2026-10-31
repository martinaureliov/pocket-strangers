extends SceneTree
## Headless GDScript test runner. Exits 0 when all tests pass, 1 otherwise.
##   godot --headless --path . --import            # once, on a fresh checkout
##   godot --headless --path . --script res://tests/test_runner.gd
##
## Each test is a method named `test_*` that returns `true` when it finishes.
## A test that hits a runtime error aborts and returns a default value, which is
## counted as a failure (bare `assert()` would hang the run instead).

const GameStateScript := preload("res://scripts/autoload/game_state.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
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


# --- Tests -------------------------------------------------------------------

func test_five_episodes_load_in_order() -> bool:
	var state := GameStateScript.new()
	var episodes: Array[Episode] = state.get_episodes()
	check_eq(episodes.size(), 5, "episode count")
	for i in episodes.size():
		check_eq(episodes[i].number, i + 1, "episode %d number" % (i + 1))
		check_eq(episodes[i].id, StringName("ep%02d" % (i + 1)), "episode %d id" % (i + 1))
	state.free()
	return true


func test_flags() -> bool:
	var state := GameStateScript.new()
	check(not state.has_flag(&"met_stranger"), "flag starts unset")
	check_eq(state.get_flag(&"met_stranger", false), false, "default returned")
	state.set_flag(&"met_stranger")
	check_eq(state.get_flag(&"met_stranger"), true, "flag set")
	state.free()
	return true


func test_save_round_trip() -> bool:
	var path := "user://test_save.json"
	var state := GameStateScript.new()
	state.current_episode = &"ep02"
	state.complete_episode(&"ep01")
	state.set_flag(&"trusted_stranger", true)
	state.set_flag(&"player_name", "Alex")
	check_eq(state.save_game(path), OK, "save ok")

	var restored := GameStateScript.new()
	check_eq(restored.load_game(path), OK, "load ok")
	check_eq(restored.current_episode, &"ep02", "current episode restored")
	check(restored.is_episode_completed(&"ep01"), "completed episode restored")
	check_eq(restored.get_flag(&"trusted_stranger"), true, "bool flag restored")
	check_eq(restored.get_flag(&"player_name"), "Alex", "string flag restored")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	state.free()
	restored.free()
	return true
