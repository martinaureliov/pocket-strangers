extends Control
## Boot scene / placeholder title screen.
## Continue and Load (when a save exists) plus one button per episode; an episode's button is
## enabled once it has an entry scene.

@onready var _episode_list: VBoxContainer = %EpisodeList
@onready var _save_screen: SaveLoadScreen = %SaveLoadScreen
@onready var _settings_screen: SettingsScreen = %SettingsScreen


func _ready() -> void:
	var latest := GameState.latest_slot()
	var nothing_loaded := GameState.current_episode == &"" and GameState.completed_episodes.is_empty()
	if nothing_loaded and not latest.is_empty():
		_load_slot(latest)  # Fresh launch: show saved progress.
	_save_screen.slot_chosen.connect(_on_slot_chosen)
	_save_screen.closed.connect(_focus_first_button)
	_settings_screen.closed.connect(_focus_first_button)
	if not latest.is_empty():
		_episode_list.add_child(_make_button("Continue", _continue))
		_episode_list.add_child(_make_button("Load", _open_load_screen))
	for episode in GameState.get_episodes():
		var label := "%d. %s" % [episode.number, episode.title]
		if GameState.is_episode_completed(episode.id):
			label += "  ✓"
		var button := _make_button(label, _start_episode.bind(episode))
		if not episode.is_playable():
			button.disabled = true
			button.tooltip_text = "Coming soon"
		_episode_list.add_child(button)
	_episode_list.add_child(_make_button("Settings", _settings_screen.open))
	_focus_first_button()


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_pressed)
	return button


func _focus_first_button() -> void:
	if _episode_list.get_child_count() > 0:
		(_episode_list.get_child(0) as Button).grab_focus()


func _start_episode(episode: Episode) -> void:
	GameState.begin_episode(episode.id)
	get_tree().change_scene_to_file(episode.entry_scene)


## Loads `slot`, returning false (and logging) if it can't be read.
func _load_slot(slot: String) -> bool:
	var err := GameState.load_slot(slot)
	if err != OK:
		push_error("Main: loading slot %s failed: %s" % [slot, error_string(err)])
		return false
	return true


## Opens the episode the loaded save was in, or refreshes this screen when the save is
## between episodes (so the progress marks update).
func _enter_loaded_game() -> void:
	var path := GameState.loaded_scene_path()
	if path.is_empty():
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(path)


func _continue() -> void:
	if _load_slot(GameState.latest_slot()):
		_enter_loaded_game()


func _open_load_screen() -> void:
	_save_screen.open(SaveLoadScreen.Mode.LOAD)


func _on_slot_chosen(slot: String) -> void:
	if _load_slot(slot):
		_enter_loaded_game()
