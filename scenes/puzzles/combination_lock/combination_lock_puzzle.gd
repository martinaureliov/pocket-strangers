extends Puzzle
## Placeholder combination-lock puzzle: turn the dials to the code, then press Open.
## The rules live in CombinationLock; this script is only the UI.

@export var code: Array[int] = [3, 1, 4]
@export var title: String = "Locked"
@export_multiline var hint: String = "Turn the dials to the right code."

var _lock: CombinationLock
var _digit_labels: Array[Label] = []
var _feedback: Label


func _ready() -> void:
	_lock = CombinationLock.new(code)
	_lock.changed.connect(_refresh)
	_build_ui()
	_refresh()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	margin.add_child(column)

	column.add_child(_label(title, 48))
	column.add_child(_label(hint, 26))

	var dials := HBoxContainer.new()
	dials.alignment = BoxContainer.ALIGNMENT_CENTER
	dials.add_theme_constant_override("separation", 32)
	column.add_child(dials)
	for i in _lock.dial_count():
		var dial := VBoxContainer.new()
		dial.add_child(_button("▲", _rotate_dial.bind(i, 1)))
		var digit := _label("0", 72)
		_digit_labels.append(digit)
		dial.add_child(digit)
		dial.add_child(_button("▼", _rotate_dial.bind(i, -1)))
		dials.add_child(dial)

	_feedback = _label("", 26)
	column.add_child(_feedback)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	column.add_child(actions)
	var open_button := _button("Open", _on_open_pressed)
	actions.add_child(open_button)
	actions.add_child(_button("Give up", _on_give_up_pressed))
	open_button.grab_focus.call_deferred()


func _refresh() -> void:
	for i in _digit_labels.size():
		_digit_labels[i].text = str(_lock.digits[i])
	_feedback.text = ""


func _rotate_dial(index: int, step: int) -> void:
	Audio.play_sfx("dial_tick")
	_lock.rotate(index, step)


func _on_open_pressed() -> void:
	if _lock.try_open():
		Audio.play_sfx("lock_open")  # Keeps playing on the Audio autoload after the puzzle closes.
		finish(true)
	else:
		Audio.play_sfx("lock_fail")
		_feedback.text = "It doesn't budge."


func _on_give_up_pressed() -> void:
	Audio.play_sfx("ui_back")
	finish(false)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 64)
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(on_pressed)
	return button
