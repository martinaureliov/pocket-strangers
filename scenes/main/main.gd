extends Control
## Boot scene / placeholder title screen.
## Continue (when a save exists) plus one button per episode; an episode's button is enabled
## once it has an entry scene.

@onready var _episode_list: VBoxContainer = %EpisodeList


func _ready() -> void:
	var nothing_loaded := GameState.current_episode == &"" and GameState.completed_episodes.is_empty()
	if nothing_loaded and GameState.has_save():
		GameState.load_game()  # Fresh launch: show saved progress.
	if GameState.has_save():
		_episode_list.add_child(_make_button("Continue", _continue))
	for episode in GameState.get_episodes():
		var label := "%d. %s" % [episode.number, episode.title]
		if GameState.is_episode_completed(episode.id):
			label += "  ✓"
		var button := _make_button(label, _start_episode.bind(episode))
		if not episode.is_playable():
			button.disabled = true
			button.tooltip_text = "Coming soon"
		_episode_list.add_child(button)
	if _episode_list.get_child_count() > 0:
		(_episode_list.get_child(0) as Button).grab_focus()


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_pressed)
	return button


func _start_episode(episode: Episode) -> void:
	GameState.begin_episode(episode.id)
	get_tree().change_scene_to_file(episode.entry_scene)


func _continue() -> void:
	if GameState.load_game() != OK:
		return
	var episode := GameState.get_episode(StringName(GameState.scene_state.get("episode", "")))
	if episode and episode.is_playable():
		get_tree().change_scene_to_file(episode.entry_scene)
	else:
		get_tree().reload_current_scene()  # Save is between episodes: refresh progress marks.
