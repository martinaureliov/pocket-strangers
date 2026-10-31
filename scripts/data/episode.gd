class_name Episode
extends Resource
## Metadata for one of the game's five episodes.
## One `episode.tres` lives in each `res://episodes/epXX/` folder.

## 1-based episode number (1..5).
@export_range(1, 5) var number: int = 1
## Stable id used in save data and story flags, e.g. "ep01".
@export var id: StringName = &""
@export var title: String = ""
@export_multiline var synopsis: String = ""
## First scene of the episode. Empty until the episode is built.
@export_file("*.tscn") var entry_scene: String = ""


func is_playable() -> bool:
	return not entry_scene.is_empty() and ResourceLoader.exists(entry_scene)
