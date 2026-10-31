class_name VNPlayer
extends Control
## Plays one episode's dialogue: background, characters, text box, choices, puzzles, and the
## reader conveniences (save/load anywhere, backlog, auto, skip-read).
##
## Dialogue scripts drive the presentation through the `Stage` alias, e.g.
##   $> Stage.background("park_day")
##   $> Stage.show_character("stranger", "smile", "right")
##   $> Stage.hide_character("stranger")
##   $> Stage.puzzle("res://scenes/puzzles/combination_lock/combination_lock_puzzle.tscn", "ep01_phone_unlocked")
## Art is found by file name (see CLAUDE.md); missing art is drawn as a labeled placeholder.

signal episode_finished

const TITLE_SCENE := "res://scenes/main/main.tscn"
const BACKGROUND_PATH := "res://assets/art/backgrounds/bg_%s.png"
const CHARACTER_PATH := "res://assets/art/characters/chr_%s_%s_%s.png"
const CHARACTER_SIZE := Vector2(620, 940)
## Horizontal screen positions characters can stand at.
const SLOTS: Dictionary = {"left": 0.22, "center": 0.5, "right": 0.78}
const FADE_TIME := 0.35
const AUTO_DELAY_BASE := 1.2
const AUTO_DELAY_PER_CHAR := 0.04
const SKIP_DELAY := 0.06

@export var dialogue: DialogueResource
@export var start_cue: String = "start"
@export var episode_id: StringName = &""
## Show choices whose condition failed as disabled buttons instead of hiding them.
@export var show_locked_choices: bool = false

var runner: StoryRunner = StoryRunner.new()
var auto_mode: bool = false
var skip_mode: bool = false

## Plain-data description of what's on screen, saved with the game.
var _stage: Dictionary = {"background": "", "characters": {}}
var _character_nodes: Dictionary = {}
var _background_node: Control
var _waiting_for_input: bool = false
var _in_puzzle: bool = false
var _line_serial: int = 0
var _auto_button: Button
var _skip_button: Button
var _backlog_list: VBoxContainer
var _backlog_scroll: ScrollContainer
var _toast_tween: Tween

@onready var _background_layer: Control = %Background
@onready var _character_layer: Control = %Characters
@onready var _dialogue_box: Control = %DialogueBox
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _dialogue_label: DialogueLabel = %DialogueLabel
@onready var _continue_marker: Label = %ContinueMarker
@onready var _choices: VBoxContainer = %Choices
@onready var _quick_menu: HBoxContainer = %QuickMenu
@onready var _puzzle_layer: Control = %PuzzleLayer
@onready var _backlog: PanelContainer = %Backlog
@onready var _toast: Label = %Toast
@onready var _save_screen: SaveLoadScreen = %SaveLoadScreen
@onready var _settings_screen: SettingsScreen = %SettingsScreen


func _ready() -> void:
	DialogueManager.register_state_context("Stage", self)
	runner.state = GameState
	runner.line_changed.connect(_on_line_changed)
	runner.ended.connect(_on_ended)
	_save_screen.slot_chosen.connect(_on_slot_chosen)
	_save_screen.closed.connect(get_viewport().gui_release_focus)  # Keep Space/Enter for advancing.
	_settings_screen.closed.connect(get_viewport().gui_release_focus)
	Settings.changed.connect(_on_settings_changed)
	_apply_text_speed()
	_build_quick_menu()
	_build_backlog()
	_dialogue_box.hide()
	_choices.hide()
	_backlog.hide()
	_toast.modulate.a = 0.0

	var saved: Dictionary = GameState.scene_state
	if not saved.is_empty() and StringName(saved.get("episode", "")) == episode_id:
		apply_stage(saved.get("stage", {}))
		runner.resume(saved.get("story", {}))
	else:
		GameState.begin_episode(episode_id)
		runner.start(dialogue, start_cue)


func _exit_tree() -> void:
	DialogueManager.unregister_state_context("Stage")
	GameState.save_system()  # Keep read lines even if the player never saves.


#region Stage commands (called from dialogue as Stage.<name>)

func background(bg_name: String) -> void:
	_stage["background"] = bg_name
	var old := _background_node
	_background_node = _make_background(bg_name)
	_background_layer.add_child(_background_node)
	if old == null or skip_mode:
		if old:
			old.queue_free()
		return
	_background_node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_background_node, "modulate:a", 1.0, FADE_TIME)
	await tween.finished
	old.queue_free()


func show_character(character: String, expression: String = "neutral", slot: String = "center", pose: String = "default") -> void:
	var characters: Dictionary = _stage["characters"]
	characters[character] = {"expression": expression, "slot": slot, "pose": pose}
	var old: Control = _character_nodes.get(character)
	var node := _make_character(character, pose, expression)
	_place_character(node, slot)
	_character_layer.add_child(node)
	_character_nodes[character] = node
	if old:
		old.queue_free()  # Expression/position change: swap instantly.
		return
	if skip_mode:
		return
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, FADE_TIME)
	await tween.finished


func hide_character(character: String) -> void:
	var characters: Dictionary = _stage["characters"]
	characters.erase(character)
	var node: Control = _character_nodes.get(character)
	_character_nodes.erase(character)
	if node == null:
		return
	if not skip_mode:
		var tween := create_tween()
		tween.tween_property(node, "modulate:a", 0.0, FADE_TIME)
		await tween.finished
	node.queue_free()


func clear_characters() -> void:
	for character: String in _character_nodes.keys():
		hide_character(character)


## Runs a puzzle scene on top of the story and waits for it. Stores the result (true = solved)
## in the story flag `result_flag`, so dialogue can branch on it.
func puzzle(scene_path: String, result_flag: String) -> bool:
	var packed := load(scene_path) as PackedScene
	var node: Node = packed.instantiate() if packed else null
	var instance := node as Puzzle
	if instance == null:
		if node:
			node.free()
		push_error("VNPlayer: %s is not a Puzzle scene" % scene_path)
		GameState.set_flag(StringName(result_flag), false)
		return false
	_set_skip(false)
	_in_puzzle = true
	_dialogue_box.hide()
	_quick_menu.hide()
	_puzzle_layer.add_child(instance)
	var solved: bool = await instance.finished
	instance.queue_free()
	_in_puzzle = false
	_quick_menu.show()
	GameState.set_flag(StringName(result_flag), solved)
	return solved

#endregion


## Rebuild the screen from saved stage data, without transitions.
func apply_stage(data: Dictionary) -> void:
	var was_skipping := skip_mode
	skip_mode = true  # Commands skip their fades in skip mode.
	var bg_name := String(data.get("background", ""))
	if not bg_name.is_empty():
		background(bg_name)
	var characters: Dictionary = data.get("characters", {})
	for character: String in characters:
		var c: Dictionary = characters[character]
		show_character(character, c.get("expression", "neutral"), c.get("slot", "center"), c.get("pose", "default"))
	skip_mode = was_skipping


#region Story flow

func _on_line_changed(line: DialogueLine) -> void:
	_line_serial += 1
	var serial := _line_serial
	_waiting_for_input = false
	_clear_choices()
	_continue_marker.hide()
	_dialogue_box.show()
	_speaker_label.text = line.character
	_speaker_label.visible = not line.character.is_empty()
	if skip_mode and not runner.line_was_seen:
		_set_skip(false)  # Skip only fast-forwards text that has been read before.
	_dialogue_label.dialogue_line = line

	if not line.text.is_empty():
		_dialogue_label.type_out()
		if skip_mode:
			_dialogue_label.skip_typing()
		if _dialogue_label.is_typing:
			await _dialogue_label.finished_typing
		if serial != _line_serial:
			return

	if runner.has_choices():
		_set_skip(false)
		_show_choices()
		return
	_waiting_for_input = true
	_continue_marker.show()
	_schedule_auto_advance(serial)


func _advance() -> void:
	if not _waiting_for_input:
		return
	_waiting_for_input = false
	_continue_marker.hide()
	runner.advance()


func _schedule_auto_advance(serial: int) -> void:
	var delay := -1.0
	if skip_mode:
		delay = SKIP_DELAY
	elif auto_mode:
		delay = (AUTO_DELAY_BASE + AUTO_DELAY_PER_CHAR * runner.line.text.length()) * Settings.auto_delay_scale()
	elif runner.line and runner.line.time != "":
		delay = AUTO_DELAY_PER_CHAR * runner.line.text.length() if runner.line.time == "auto" else runner.line.time.to_float()
	if delay < 0.0:
		return
	await get_tree().create_timer(delay).timeout
	if serial == _line_serial and _waiting_for_input and not _overlay_open():
		_advance()


func _show_choices() -> void:
	var first: Button = null
	for response: DialogueResponse in runner.line.responses:
		if not response.is_allowed and not show_locked_choices:
			continue
		var button := Button.new()
		button.text = response.text
		button.disabled = not response.is_allowed
		button.custom_minimum_size = Vector2(720, 64)
		button.add_theme_font_size_override("font_size", 30)
		button.pressed.connect(_on_choice_pressed.bind(response))
		_choices.add_child(button)
		if first == null and response.is_allowed:
			first = button
	_choices.show()
	if first:
		first.grab_focus()


func _on_choice_pressed(response: DialogueResponse) -> void:
	_clear_choices()
	runner.choose(response)


func _clear_choices() -> void:
	_choices.hide()
	for child in _choices.get_children():
		child.queue_free()


func _on_ended() -> void:
	_dialogue_box.hide()
	_clear_choices()
	if episode_id != &"":
		GameState.complete_episode(episode_id)
	GameState.scene_state = {}
	var err := GameState.save_slot(GameState.AUTO_SLOT)  # Keep episode completion.
	if err != OK:
		push_error("VNPlayer: autosave failed: %s" % error_string(err))
	episode_finished.emit()
	_show_toast("End of episode")
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(TITLE_SCENE)

#endregion


#region Input

func _unhandled_input(event: InputEvent) -> void:
	if _save_screen.visible or _settings_screen.visible:
		return
	if _backlog.visible:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_toggle_backlog()
		return
	if _in_puzzle:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		get_viewport().set_input_as_handled()
		_toggle_backlog()
		return
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not (clicked or event.is_action_pressed("ui_accept")):
		return
	get_viewport().set_input_as_handled()
	if _dialogue_label.is_typing:
		_dialogue_label.skip_typing()
	elif _waiting_for_input:
		_set_skip(false)
		_advance()

#endregion


#region Save / load

func can_save() -> bool:
	return not _in_puzzle and not runner.is_busy() and runner.line != null


func save_game(slot: String) -> Error:
	if not can_save():
		return ERR_BUSY
	GameState.scene_state = {
		"episode": String(episode_id),
		"story": runner.snapshot(),
		"stage": _stage.duplicate(true),
	}
	return GameState.save_slot(slot)


func load_game(slot: String) -> void:
	var err := GameState.load_slot(slot)
	if err != OK:
		_show_toast("Load failed: %s" % error_string(err))
		return
	var path := GameState.loaded_scene_path()
	get_tree().change_scene_to_file(path if not path.is_empty() else TITLE_SCENE)


func _open_save_screen() -> void:
	if not can_save():
		_show_toast("Can't save right now")
		return
	_set_skip(false)
	_save_screen.open(SaveLoadScreen.Mode.SAVE)


func _open_load_screen() -> void:
	_set_skip(false)
	_save_screen.open(SaveLoadScreen.Mode.LOAD)


func _on_slot_chosen(slot: String) -> void:
	if _save_screen.mode == SaveLoadScreen.Mode.LOAD:
		load_game(slot)
		return
	var err := save_game(slot)
	_save_screen.close()
	_show_toast(("Saved to slot %s" % slot) if err == OK else "Save failed: %s" % error_string(err))

#endregion


#region Settings

func _open_settings_screen() -> void:
	_set_skip(false)
	_settings_screen.open()


func _on_settings_changed(_key: StringName) -> void:
	_apply_text_speed()


func _apply_text_speed() -> void:
	_dialogue_label.seconds_per_step = Settings.seconds_per_char()

#endregion


#region UI

func _build_quick_menu() -> void:
	_quick_menu.add_child(_menu_button("Save", _open_save_screen))
	_quick_menu.add_child(_menu_button("Load", _open_load_screen))
	_quick_menu.add_child(_menu_button("Log", _toggle_backlog))
	_auto_button = _menu_button("Auto", _set_auto, true)
	_quick_menu.add_child(_auto_button)
	_skip_button = _menu_button("Skip", _set_skip, true)
	_quick_menu.add_child(_skip_button)
	_quick_menu.add_child(_menu_button("Settings", _open_settings_screen))
	_quick_menu.add_child(_menu_button("Title", get_tree().change_scene_to_file.bind(TITLE_SCENE)))


func _menu_button(text: String, action: Callable, toggle: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE  # Keep Space/Enter for advancing text.
	button.custom_minimum_size = Vector2(110, 48)
	button.add_theme_font_size_override("font_size", 24)
	button.toggle_mode = toggle
	if toggle:
		button.toggled.connect(action)
	else:
		button.pressed.connect(action)
	return button


func _set_auto(enabled: bool) -> void:
	auto_mode = enabled
	_auto_button.set_pressed_no_signal(enabled)
	if enabled and _waiting_for_input:
		_schedule_auto_advance(_line_serial)


func _set_skip(enabled: bool) -> void:
	skip_mode = enabled
	if _skip_button:
		_skip_button.set_pressed_no_signal(enabled)
	if not enabled:
		return
	if _dialogue_label.is_typing:
		_dialogue_label.skip_typing()
	elif _waiting_for_input:
		if runner.line_was_seen:
			_schedule_auto_advance(_line_serial)
		else:
			_set_skip(false)
			_show_toast("Nothing read to skip")


func _build_backlog() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	_backlog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Log"
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	_backlog_scroll = ScrollContainer.new()
	_backlog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_backlog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_backlog_scroll)
	_backlog_list = VBoxContainer.new()
	_backlog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backlog_list.add_theme_constant_override("separation", 12)
	_backlog_scroll.add_child(_backlog_list)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 52)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_toggle_backlog)
	column.add_child(close)


func _toggle_backlog() -> void:
	if _backlog.visible:
		_backlog.hide()
		return
	for child in _backlog_list.get_children():
		child.queue_free()
	for entry: Dictionary in runner.history:
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.add_theme_font_size_override("normal_font_size", 26)
		label.add_theme_font_size_override("bold_font_size", 26)
		var speaker := String(entry.get("speaker", ""))
		var text := String(entry.get("text", ""))
		label.text = ("[b]%s[/b]  %s" % [speaker, text]) if not speaker.is_empty() else text
		_backlog_list.add_child(label)
	_backlog.show()
	await get_tree().process_frame
	_backlog_scroll.scroll_vertical = int(_backlog_scroll.get_v_scroll_bar().max_value)


func _overlay_open() -> bool:
	return _backlog.visible or _save_screen.visible or _settings_screen.visible


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _make_background(bg_name: String) -> Control:
	var path := BACKGROUND_PATH % bg_name
	var node: Control
	if ResourceLoader.exists(path):
		var rect := TextureRect.new()
		rect.texture = load(path)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		node = rect
	else:
		var color := ColorRect.new()
		color.color = Color.from_hsv(float(absi(hash(bg_name)) % 360) / 360.0, 0.35, 0.3)
		var label := _placeholder_label("background: %s\n(missing %s)" % [bg_name, path.get_file()], 28)
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		label.position.y = 120
		color.add_child(label)
		node = color
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _make_character(character: String, pose: String, expression: String) -> Control:
	var path := CHARACTER_PATH % [character, pose, expression]
	if ResourceLoader.exists(path):
		var rect := TextureRect.new()
		rect.texture = load(path)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.from_hsv(float(absi(hash(character)) % 360) / 360.0, 0.45, 0.65, 0.9)
	style.set_corner_radius_all(48)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _placeholder_label("%s\n(%s)" % [character.capitalize(), expression], 40)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _place_character(node: Control, slot: String) -> void:
	var x: float = SLOTS.get(slot, 0.5)
	node.anchor_left = x
	node.anchor_right = x
	node.anchor_top = 1.0
	node.anchor_bottom = 1.0
	node.offset_left = -CHARACTER_SIZE.x / 2.0
	node.offset_right = CHARACTER_SIZE.x / 2.0
	node.offset_top = -CHARACTER_SIZE.y
	node.offset_bottom = 0.0


func _placeholder_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

#endregion
