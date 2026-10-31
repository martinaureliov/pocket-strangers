extends Control
## Boot scene / placeholder title screen.
## Lists the five episodes; an episode's button is enabled once it has an entry scene.

@onready var _episode_list: VBoxContainer = %EpisodeList


func _ready() -> void:
	for episode in GameState.get_episodes():
		var button := Button.new()
		button.text = "%d. %s" % [episode.number, episode.title]
		button.custom_minimum_size = Vector2(0, 56)
		button.add_theme_font_size_override("font_size", 28)
		if episode.is_playable():
			button.pressed.connect(_start_episode.bind(episode))
		else:
			button.disabled = true
			button.tooltip_text = "Coming soon"
		_episode_list.add_child(button)


func _start_episode(episode: Episode) -> void:
	GameState.current_episode = episode.id
	get_tree().change_scene_to_file(episode.entry_scene)
