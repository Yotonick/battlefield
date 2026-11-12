extends CanvasLayer
## Меню по Esc. Игра по сети не ставится на паузу — боец просто стоит,
## пока курсор свободен (см. Player._read_input).

@onready var _info: Label = %Info
@onready var _resume_button: Button = %ResumeButton
@onready var _team_button: Button = %TeamButton
@onready var _leave_button: Button = %LeaveButton
@onready var _quit_button: Button = %QuitButton
var _loadout_button: Button


func _ready() -> void:
	visible = false
	_resume_button.pressed.connect(close)
	_team_button.pressed.connect(_on_team_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_loadout_button = Button.new()
	_loadout_button.text = "Снаряжение (B)"
	_loadout_button.custom_minimum_size = _team_button.custom_minimum_size
	_loadout_button.pressed.connect(_on_loadout_pressed)
	_team_button.add_sibling(_loadout_button)
	_build_settings()


## Ползунки настроек (GameSettings): применяются сразу.
func _build_settings() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	_info.add_sibling(box)
	_add_slider(box, GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, GameSettings.get_fov(),
			func(value: float) -> String:
				var aspect: float = get_viewport().get_visible_rect().size.aspect()
				return "Угол обзора: %d° (по горизонтали %d°)" % [roundi(value),
						roundi(GameSettings.horizontal_fov(value, aspect))],
			func(value: float) -> void: GameSettings.set_fov(value))
	_add_slider(box, GameSettings.SENS_MIN, GameSettings.SENS_MAX, 0.005, GameSettings.get_sensitivity(),
			func(value: float) -> String: return "Чувствительность мыши: %.3f" % value,
			func(value: float) -> void: GameSettings.set_sensitivity(value))


func _add_slider(box: VBoxContainer, min_value: float, max_value: float, step: float, value: float,
		caption: Callable, apply: Callable) -> void:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", 14)
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 22)
	box.add_child(slider)
	label.text = caption.call(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		apply.call(new_value)
		label.text = caption.call(new_value))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"release_mouse"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif not visible and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# Например, после Alt+Tab: клик по игре снова захватывает мышь.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leave_button.text = "Завершить игру (все вылетят)" if Network.is_host() else "Выйти в меню"
	if Network.is_host():
		var addresses: PackedStringArray = Network.get_local_ipv4_addresses()
		_info.text = "Вы хост. Друзья подключаются к: %s (порт %d)" % [
			", ".join(addresses) if not addresses.is_empty() else "?", Network.port]
	else:
		_info.text = "Пинг до хоста: %d мс" % Network.get_ping_ms()
	var rules: TdmRules = TdmRules.get_rules(get_tree())
	_team_button.visible = rules != null and rules.get_local_team() != TdmRules.TEAM_NONE
	_resume_button.grab_focus()


func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_team_pressed() -> void:
	var team_select: Node = get_tree().get_first_node_in_group(&"team_select")
	visible = false
	if team_select != null:
		team_select.call(&"open")


func _on_loadout_pressed() -> void:
	var menu: Node = get_tree().get_first_node_in_group(&"loadout_menu")
	visible = false
	if menu != null:
		menu.call(&"open")


func _on_leave_pressed() -> void:
	Network.leave()


func _on_quit_pressed() -> void:
	Network.leave()
	get_tree().quit()
