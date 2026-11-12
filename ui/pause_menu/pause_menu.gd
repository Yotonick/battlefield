extends CanvasLayer
## Меню по Esc. Игра по сети не ставится на паузу — боец просто стоит,
## пока курсор свободен (см. Player._read_input).

@onready var _info: Label = %Info
@onready var _resume_button: Button = %ResumeButton
@onready var _team_button: Button = %TeamButton
@onready var _leave_button: Button = %LeaveButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	_resume_button.pressed.connect(close)
	_team_button.pressed.connect(_on_team_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


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


func _on_leave_pressed() -> void:
	Network.leave()


func _on_quit_pressed() -> void:
	Network.leave()
	get_tree().quit()
