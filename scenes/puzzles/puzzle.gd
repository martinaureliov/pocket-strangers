class_name Puzzle
extends Control
## Base class for puzzle scenes. The VN player adds a puzzle on top of the story, waits for
## `finished`, writes the result to a story flag, then removes the puzzle.

signal finished(solved: bool)

var _done: bool = false


## Call exactly once when the player solves or gives up.
func finish(solved: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(solved)
