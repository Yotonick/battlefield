extends CanvasLayer
## Экран выбора команды. Открывается сам, пока у игрока нет команды,
## и по кнопке «Сменить команду» в меню Esc. Команду выбирает игрок
## (решение владельца); «Авто» — в команду, где меньше людей.
## Всё собирается кодом — сцена team_select.tscn содержит только этот скрипт.

const GROUP: StringName = &"team_select"

var _rules: TdmRules
var _manual_open: bool = false
var _team_buttons: Array[Button] = []
var _auto_button: Button
var _close_button: Button
var _hint: Label
## Нажали кнопку — ждём ответа хоста, чтобы не слать запрос дважды.
var _pending_team: int = -1
var _team_before: int = 0
var _pending_since_ms: int = 0


func _ready() -> void:
	layer = 15
	add_to_group(GROUP)
	_build()
	visible = false
	_rules = TdmRules.get_rules(get_tree())
	if _rules == null:
		_rules = get_parent().get_node_or_null(^"Rules") as TdmRules


## Вызывается из меню паузы.
func open() -> void:
	_manual_open = true
	_pending_team = -1


func close() -> void:
	_manual_open = false
	if visible:
		visible = false
		if not _is_pause_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _rules == null:
		return
	var my_id: int = multiplayer.get_unique_id()
	var registered: bool = _rules.teams.has(my_id)
	var my_team: int = _rules.get_team(my_id)
	if _pending_team >= 0:
		# Хост принял выбор (для «Авто» команда могла и не поменяться).
		var waited: bool = Time.get_ticks_msec() - _pending_since_ms > 1500
		var accepted: bool = my_team == _pending_team or (_pending_team == 0 and my_team != TdmRules.TEAM_NONE
				and (my_team != _team_before or waited))
		if accepted:
			_manual_open = false
			_pending_team = -1
		elif waited:
			_pending_team = -1  # хост не ответил — даём нажать снова
	# Автовыбор из командной строки (--team=) — экран не нужен.
	var auto_pick: bool = Network.requested_team >= 0
	var should_show: bool = registered and (_manual_open or (my_team == TdmRules.TEAM_NONE and not auto_pick))
	if should_show != visible:
		visible = should_show
		if not visible and not _is_pause_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not visible:
		return
	if not _is_pause_open():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh(my_team)


func _unhandled_input(event: InputEvent) -> void:
	# Esc закрывает экран, если команда уже есть (иначе откроется меню паузы).
	if visible and event.is_action_pressed(&"release_mouse") and _rules != null \
			and _rules.get_local_team() != TdmRules.TEAM_NONE:
		close()
		get_viewport().set_input_as_handled()


func _refresh(my_team: int) -> void:
	for team: int in [TdmRules.TEAM_BLUE, TdmRules.TEAM_RED]:
		var names := PackedStringArray()
		for peer_id: int in _rules.teams:
			if _rules.teams[peer_id] == team:
				names.append(Network.get_player_name(peer_id))
		var button: Button = _team_buttons[team - 1]
		var lines := PackedStringArray()
		lines.append(TdmRules.TEAM_NAMES[team].to_upper())
		lines.append("игроков: %d   счёт: %d" % [names.size(), _rules.scores[team]])
		lines.append(", ".join(names) if not names.is_empty() else "—")
		if team == my_team:
			lines.append("(вы здесь)")
		button.text = "\n".join(lines)
		button.disabled = _pending_team >= 0 or team == my_team
	_auto_button.disabled = _pending_team >= 0
	_close_button.visible = my_team != TdmRules.TEAM_NONE
	var blue: int = _rules.count_team(TdmRules.TEAM_BLUE)
	var red: int = _rules.count_team(TdmRules.TEAM_RED)
	if absi(blue - red) >= 2:
		_hint.text = "Команды неравные (%d против %d) — кому-то стоит перейти." % [blue, red]
	elif my_team != TdmRules.TEAM_NONE:
		_hint.text = "Смена команды — без штрафа: вы просто появитесь на базе новой команды."
	else:
		_hint.text = "Огня по своим нет: пули пролетают сквозь союзников."


func _choose(team: int) -> void:
	_pending_team = team
	_team_before = _rules.get_local_team()
	_pending_since_ms = Time.get_ticks_msec()
	_rules.request_team(team)


func _open_loadout() -> void:
	var menu: Node = get_tree().get_first_node_in_group(&"loadout_menu")
	if menu != null:
		menu.call(&"open")


func _is_pause_open() -> bool:
	var pause := get_parent().get_node_or_null(^"PauseMenu") as CanvasLayer
	return pause != null and pause.visible


# --- Построение -----------------------------------------------------------

func _build() -> void:
	# Затемнение ловит клики — иначе меню паузы захватило бы мышь.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.1, 0.95)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ВЫБОР КОМАНДЫ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 28)
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	vbox.add_child(row)
	for team: int in [TdmRules.TEAM_BLUE, TdmRules.TEAM_RED]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(280, 150)
		button.add_theme_font_size_override(&"font_size", 18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var color: Color = TdmRules.TEAM_COLORS[team]
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			var k: float = 0.3 if state == "normal" or state == "focus" else (0.45 if state == "hover" else 0.2)
			box.bg_color = Color(color.r * k, color.g * k, color.b * k, 0.95)
			box.border_color = color
			box.set_border_width_all(2 if state != "disabled" else 1)
			box.set_corner_radius_all(4)
			if state == "focus":
				box.draw_center = false
			button.add_theme_stylebox_override(StringName(state), box)
		button.add_theme_color_override(&"font_disabled_color", Color(0.75, 0.75, 0.72))
		button.pressed.connect(_choose.bind(team))
		row.add_child(button)
		_team_buttons.append(button)

	_auto_button = Button.new()
	_auto_button.text = "Авто — в команду, где меньше игроков"
	_auto_button.custom_minimum_size = Vector2(0, 40)
	_auto_button.pressed.connect(_choose.bind(0))
	vbox.add_child(_auto_button)

	var loadout_button := Button.new()
	loadout_button.text = "Снаряжение (B) — выбрать оружие"
	loadout_button.custom_minimum_size = Vector2(0, 34)
	loadout_button.pressed.connect(_open_loadout)
	vbox.add_child(loadout_button)

	_close_button = Button.new()
	_close_button.text = "Остаться в своей команде (Esc)"
	_close_button.custom_minimum_size = Vector2(0, 34)
	_close_button.pressed.connect(close)
	vbox.add_child(_close_button)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.68))
	_hint.add_theme_font_size_override(&"font_size", 14)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(_hint)
