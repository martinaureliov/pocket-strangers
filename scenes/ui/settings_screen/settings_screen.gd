class_name SettingsScreen
extends Control
## Full-screen settings: text speed, auto speed, volumes and fullscreen. Every change goes to the
## `Settings` autoload at once; the file is saved when the screen closes. A preview line types out
## at the chosen text speed. Esc or Back closes it.

signal closed

const LABEL_WIDTH := 360.0
const CONTROL_WIDTH := 560.0
const VALUE_WIDTH := 140.0
const SLIDER_HEIGHT := 40.0
const PREVIEW_TEXT := "This is how fast the story text will appear."
## Rows in display order: [setting key, label, kind].
const ROWS: Array = [
	[&"text_speed", "Text speed", &"text_speed"],
	[&"auto_speed", "Auto speed", &"percent"],
	[&"master_volume", "Master volume", &"volume"],
	[&"music_volume", "Music volume", &"volume"],
	[&"sfx_volume", "Sound effects", &"volume"],
	[&"voice_volume", "Voice", &"volume"],
	[&"fullscreen", "Fullscreen", &"toggle"],
]

## Setting key (StringName) -> the HSlider or CheckButton that edits it. Tests drive these.
var controls: Dictionary = {}

var _value_labels: Dictionary = {}
var _kinds: Dictionary = {}
var _preview_label: Label
var _preview_elapsed: float = 0.0
var _defaults_button: Button
var _back_button: Button


func _ready() -> void:
	_build_ui()
	set_process(false)
	hide()
	visibility_changed.connect(_on_visibility_changed)


## Shows the screen with every control matching the current settings and restarts the preview.
func open() -> void:
	_sync_controls()
	show()
	(controls[&"text_speed"] as Control).grab_focus()
	_restart_preview()


## Hides the screen and saves the settings.
func close() -> void:
	if not visible:
		return
	hide()
	var err: Error = Settings.save()
	if err != OK:
		push_error("SettingsScreen: could not save settings: %s" % error_string(err))
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()  # Modal: nothing behind the screen reacts.
	if event.is_action_pressed("ui_cancel"):
		close()


func _process(delta: float) -> void:
	var total := PREVIEW_TEXT.length()
	var per_char: float = Settings.seconds_per_char()
	if per_char <= 0.0:
		_preview_label.visible_characters = -1
		set_process(false)
		return
	_preview_elapsed += delta
	var shown := int(_preview_elapsed / per_char)
	if shown >= total:
		_preview_label.visible_characters = -1
		set_process(false)
	else:
		_preview_label.visible_characters = shown


func _on_visibility_changed() -> void:
	if not visible:
		set_process(false)


func _restart_preview() -> void:
	_preview_elapsed = 0.0
	if Settings.seconds_per_char() <= 0.0:
		_preview_label.visible_characters = -1
		set_process(false)
		return
	_preview_label.visible_characters = 0
	set_process(true)


func _sync_controls() -> void:
	for key: StringName in controls:
		var value: Variant = Settings.get_value(key)
		if controls[key] is CheckButton:
			(controls[key] as CheckButton).set_pressed_no_signal(value)
		else:
			(controls[key] as Range).set_value_no_signal(value)
		_update_value_text(key)


func _on_slider_changed(value: float, key: StringName) -> void:
	Settings.set_value(key, value)
	_update_value_text(key)
	if key == &"text_speed":
		_restart_preview()


func _on_toggled(pressed: bool, key: StringName) -> void:
	Settings.set_value(key, pressed)
	_update_value_text(key)


func _on_defaults_pressed() -> void:
	Settings.reset_to_defaults()
	_sync_controls()
	_restart_preview()


func _update_value_text(key: StringName) -> void:
	var label: Label = _value_labels[key]
	var value: Variant = Settings.get_value(key)
	match _kinds[key]:
		&"toggle":
			label.text = "On" if value else "Off"
		&"volume":
			label.text = "Off" if float(value) <= 0.0 else "%d%%" % roundi(float(value) * 100.0)
		&"text_speed":
			label.text = "Instant" if float(value) >= 1.0 else "%d%%" % roundi(float(value) * 100.0)
		_:
			label.text = "%d%%" % roundi(float(value) * 100.0)


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

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	column.add_child(rows)
	for row: Array in ROWS:
		rows.add_child(_build_row(row[0], row[1], row[2]))

	var preview_panel := PanelContainer.new()
	column.add_child(preview_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	preview_panel.add_child(margin)
	_preview_label = Label.new()
	_preview_label.name = "PreviewLabel"
	_preview_label.text = PREVIEW_TEXT
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(LABEL_WIDTH + CONTROL_WIDTH + VALUE_WIDTH, 0)
	_preview_label.add_theme_font_size_override("font_size", 30)
	margin.add_child(_preview_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 24)
	column.add_child(actions)
	_defaults_button = _action_button("Defaults", _on_defaults_pressed)
	_defaults_button.name = "DefaultsButton"
	actions.add_child(_defaults_button)
	_back_button = _action_button("Back", close)
	_back_button.name = "BackButton"
	actions.add_child(_back_button)


func _build_row(key: StringName, text: String, kind: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	row.add_child(label)

	var control: Control
	var slot: Control  # What goes in the row: the control itself, or a holder that keeps a toggle left-aligned.
	if kind == &"toggle":
		var check := CheckButton.new()
		check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		check.toggled.connect(_on_toggled.bind(key))
		control = check
		var holder := HBoxContainer.new()
		holder.custom_minimum_size = Vector2(CONTROL_WIDTH, SLIDER_HEIGHT)
		holder.add_child(check)
		slot = holder
	else:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_on_slider_changed.bind(key))
		control = slider
		control.custom_minimum_size = Vector2(CONTROL_WIDTH, SLIDER_HEIGHT)
		slot = control
	control.name = String(key).to_pascal_case()
	row.add_child(slot)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 28)
	row.add_child(value_label)

	controls[key] = control
	_value_labels[key] = value_label
	_kinds[key] = kind
	return row


func _action_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_pressed)
	return button
