class_name SaveLoadScreen
extends Control
## Full-screen list of save slots, for saving or loading. Emits `slot_chosen` with the slot id;
## the owner does the actual save or load. In save mode the autosave slot is read-only and
## saving over a used slot asks first. Esc or Back closes it.

signal slot_chosen(slot: String)
signal closed

enum Mode { SAVE, LOAD }

const COLUMNS := 2
const SLOT_SIZE := Vector2(800, 136)

var mode: Mode = Mode.LOAD

var _title: Label
var _grid: GridContainer
var _back_button: Button
var _confirm: PanelContainer
var _confirm_label: Label
var _confirm_yes: Button
var _pending_slot: String = ""


func _ready() -> void:
	_build_ui()
	hide()


## Shows the screen in `new_mode` with up-to-date slot info.
func open(new_mode: Mode) -> void:
	mode = new_mode
	_title.text = "Save" if mode == Mode.SAVE else "Load"
	_confirm.hide()
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## Back button / Esc: close with the "back" sound (owners closing it after a save stay quiet).
func _close_with_sound() -> void:
	if visible:
		Audio.play_sfx("ui_back")
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()  # Modal: nothing behind the screen reacts.
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_cancel_confirm()
		else:
			_close_with_sound()


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var first: Button = null
	for slot in GameState.slot_ids():
		var button := _slot_button(slot, GameState.slot_info(slot))
		_grid.add_child(button)
		if first == null and not button.disabled:
			first = button
	(first if first else _back_button).grab_focus()


func _slot_button(slot: String, info: Dictionary) -> Button:
	var name_text := "Auto" if slot == GameState.AUTO_SLOT else "Slot %s" % slot
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 28)
	if info.is_empty():
		button.text = "%s\nEmpty" % name_text
		button.disabled = mode == Mode.LOAD
	else:
		var episode := GameState.get_episode(StringName(info["episode"]))
		var episode_text := episode.title if episode else "No episode"
		var detail := String(info["preview"]) if info["in_episode"] else "Between episodes"
		button.text = "%s   ·   %s   ·   %s\n%s" % [name_text, episode_text, _format_time(int(info["saved_at"])), detail]
	if slot == GameState.AUTO_SLOT and mode == Mode.SAVE:
		button.disabled = true
		button.tooltip_text = "Saved automatically at the end of each episode."
	button.pressed.connect(_on_slot_pressed.bind(slot, not info.is_empty()))
	return button


func _on_slot_pressed(slot: String, used: bool) -> void:
	Audio.play_sfx("ui_click")
	if mode == Mode.SAVE and used:
		_pending_slot = slot
		_confirm_label.text = "Save over slot %s?" % slot
		_confirm.show()
		_confirm_yes.grab_focus()
		return
	slot_chosen.emit(slot)


func _on_confirm_yes() -> void:
	Audio.play_sfx("ui_click")
	_confirm.hide()
	slot_chosen.emit(_pending_slot)


func _cancel_confirm() -> void:
	Audio.play_sfx("ui_back")
	_confirm.hide()
	_refresh()


## "2026-10-31  14:22" in the player's local time.
func _format_time(unix_time: int) -> String:
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d-%02d-%02d  %02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.045, 0.08, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 48)
	column.add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 16)
	column.add_child(_grid)

	_back_button = _action_button("Back", _close_with_sound)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_back_button)

	_confirm = PanelContainer.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_confirm)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	_confirm.add_child(margin)
	var confirm_column := VBoxContainer.new()
	confirm_column.add_theme_constant_override("separation", 24)
	margin.add_child(confirm_column)
	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", 34)
	confirm_column.add_child(_confirm_label)
	var confirm_actions := HBoxContainer.new()
	confirm_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_actions.add_theme_constant_override("separation", 24)
	confirm_column.add_child(confirm_actions)
	_confirm_yes = _action_button("Save", _on_confirm_yes)
	confirm_actions.add_child(_confirm_yes)
	confirm_actions.add_child(_action_button("Cancel", _cancel_confirm))
	_confirm.hide()


func _action_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_pressed)
	return button
