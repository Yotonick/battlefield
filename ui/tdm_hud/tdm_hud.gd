extends CanvasLayer
## Интерфейс TDM: счёт и таймер сверху, баннеры («Раунд начался»),
## таблица по командам (Tab, пока зажат) и экран итогов раунда.
## Всё собирается кодом — сцена tdm_hud.tscn содержит только этот скрипт.

const BANNER_TIME: float = 3.0
const TABLE_REFRESH: float = 0.25

var _rules: TdmRules
var _blue_score: Label
var _red_score: Label
var _timer_label: Label
var _goal_label: Label
var _top_bar: Control
var _banner: Label
var _banner_tween: Tween
var _waiting_label: Label

var _board: CenterContainer
var _board_title: Label
var _board_subtitle: Label
var _board_columns: Array[VBoxContainer] = []
var _board_team_headers: Array[Label] = []
var _board_grids: Array[GridContainer] = []
var _board_footer: Label
var _board_refresh: float = 0.0
var _audio: AudioStreamPlayer


func _ready() -> void:
	layer = 6
	_build()
	_rules = TdmRules.get_rules(get_tree())
	if _rules == null:
		_rules = get_parent().get_node_or_null(^"Rules") as TdmRules
	if _rules != null:
		_rules.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	if _rules == null:
		return
	var registered: bool = _rules.teams.has(multiplayer.get_unique_id())
	_top_bar.visible = registered
	_update_top_bar()

	var ended: bool = _rules.phase == TdmRules.Phase.ENDED
	var show_board: bool = registered and (ended or Input.is_action_pressed(&"player_list"))
	if show_board != _board.visible:
		_board.visible = show_board
		_board_refresh = 0.0
	if show_board:
		_board_refresh -= delta
		if _board_refresh <= 0.0:
			_board_refresh = TABLE_REFRESH
			_refresh_board()

	_waiting_label.visible = registered and _rules.phase == TdmRules.Phase.WAITING and not show_board


# --- Верхняя панель -------------------------------------------------------

func _update_top_bar() -> void:
	_blue_score.text = str(_rules.scores[TdmRules.TEAM_BLUE])
	_red_score.text = str(_rules.scores[TdmRules.TEAM_RED])
	match _rules.phase:
		TdmRules.Phase.WAITING:
			_timer_label.text = "--:--"
			_goal_label.text = "ожидание игроков"
		TdmRules.Phase.PLAYING:
			_timer_label.text = _format_time(_rules.time_left)
			_goal_label.text = "TDM · до %d убийств" % _rules.kill_limit
		TdmRules.Phase.ENDED:
			_timer_label.text = "0:00"
			_goal_label.text = "раунд окончен"
	# Последняя минута — таймер красным.
	var urgent: bool = _rules.phase == TdmRules.Phase.PLAYING and _rules.time_left < 60.0
	_timer_label.modulate = Color(1.0, 0.55, 0.45) if urgent else Color.WHITE
	# Своя команда — крупнее.
	var my_team: int = _rules.get_local_team()
	_blue_score.add_theme_font_size_override(&"font_size", 38 if my_team == TdmRules.TEAM_BLUE else 30)
	_red_score.add_theme_font_size_override(&"font_size", 38 if my_team == TdmRules.TEAM_RED else 30)


static func _format_time(seconds: float) -> String:
	var total: int = ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [total / 60, total % 60]


func _on_phase_changed(new_phase: TdmRules.Phase, old_phase: TdmRules.Phase) -> void:
	match new_phase:
		TdmRules.Phase.PLAYING:
			_show_banner("РАУНД %d — В БОЙ!" % _rules.round_number, Color(0.95, 0.92, 0.8))
			_play(&"round_start")
		TdmRules.Phase.ENDED:
			_play(&"round_end")
		TdmRules.Phase.WAITING:
			if old_phase == TdmRules.Phase.PLAYING:
				_show_banner("Раунд прерван: в одной из команд никого нет", Color(1.0, 0.7, 0.5))


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.modulate = color
	_banner.modulate.a = 1.0
	_banner.visible = true
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = _banner.create_tween()
	_banner_tween.tween_interval(BANNER_TIME)
	_banner_tween.tween_property(_banner, ^"modulate:a", 0.0, 0.6)


func _play(sound: StringName) -> void:
	_audio.stream = ProcSounds.get_sound(sound)
	_audio.play()


# --- Таблица и итоги ------------------------------------------------------

func _refresh_board() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var my_team: int = _rules.get_local_team()
	if _rules.phase == TdmRules.Phase.ENDED:
		if _rules.winner == TdmRules.TEAM_NONE:
			_board_title.text = "НИЧЬЯ"
			_board_title.modulate = Color(0.9, 0.9, 0.85)
		else:
			var verdict: String = ""
			if my_team != TdmRules.TEAM_NONE:
				verdict = "  —  ВЫ ПОБЕДИЛИ" if my_team == _rules.winner else "  —  ВЫ ПРОИГРАЛИ"
			_board_title.text = "ПОБЕДА: %s%s" % [TdmRules.TEAM_NAMES[_rules.winner].to_upper(), verdict]
			_board_title.modulate = TdmRules.TEAM_COLORS[_rules.winner]
		_board_subtitle.text = "Счёт %d : %d · новый раунд через %d с" % [
			_rules.scores[TdmRules.TEAM_BLUE], _rules.scores[TdmRules.TEAM_RED], ceili(_rules.time_left)]
	else:
		_board_title.text = "КОМАНДНЫЙ БОЙ"
		_board_title.modulate = Color.WHITE
		if _rules.phase == TdmRules.Phase.WAITING:
			_board_subtitle.text = "Ожидание: нужен хотя бы один игрок в каждой команде"
		else:
			_board_subtitle.text = "До %d убийств · осталось %s · раунд %d" % [
				_rules.kill_limit, _format_time(_rules.time_left), _rules.round_number]

	# Счёт бойцов (у кого боец ещё не создан — нули).
	var stats: Dictionary[int, Vector2i] = {}
	for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
		var soldier := node as Player
		if soldier != null:
			stats[soldier.peer_id] = Vector2i(soldier.kills, soldier.deaths)

	var unassigned := PackedStringArray()
	for team: int in [TdmRules.TEAM_BLUE, TdmRules.TEAM_RED]:
		var index: int = team - 1
		var header: Label = _board_team_headers[index]
		header.text = "%s   %d" % [TdmRules.TEAM_NAMES[team].to_upper(), _rules.scores[team]]
		var grid: GridContainer = _board_grids[index]
		for child: Node in grid.get_children():
			child.free()
		for title: String in ["Игрок", "Убийств", "Смертей"]:
			grid.add_child(_cell(title, 14, Color(0.7, 0.72, 0.68), title != "Игрок"))
		var rows: Array[Array] = []
		for peer_id: int in _rules.teams:
			if _rules.teams[peer_id] != team:
				continue
			var score: Vector2i = stats.get(peer_id, Vector2i.ZERO)
			rows.append([peer_id, score])
		# Лучшие сверху: больше убийств, при равенстве — меньше смертей.
		rows.sort_custom(func(a: Array, b: Array) -> bool:
			var sa: Vector2i = a[1]
			var sb: Vector2i = b[1]
			return sa.x > sb.x or (sa.x == sb.x and sa.y < sb.y))
		for row: Array in rows:
			var peer_id: int = row[0]
			var score: Vector2i = row[1]
			var tags := PackedStringArray()
			if peer_id == 1:
				tags.append("хост")
			var player_name: String = Network.get_player_name(peer_id)
			if not tags.is_empty():
				player_name += "  (%s)" % ", ".join(tags)
			var color: Color = Color(1.0, 0.9, 0.55) if peer_id == my_id else Color.WHITE
			grid.add_child(_cell(player_name, 18, color, false))
			grid.add_child(_cell(str(score.x), 18, color, true))
			grid.add_child(_cell(str(score.y), 18, color, true))
		if rows.is_empty():
			grid.add_child(_cell("—", 18, Color(0.6, 0.6, 0.6), false))
			grid.add_child(_cell("", 18, Color.WHITE, true))
			grid.add_child(_cell("", 18, Color.WHITE, true))
	for peer_id: int in _rules.teams:
		if _rules.teams[peer_id] == TdmRules.TEAM_NONE:
			unassigned.append(Network.get_player_name(peer_id))

	var footer := PackedStringArray()
	if not unassigned.is_empty():
		footer.append("Выбирают команду: %s" % ", ".join(unassigned))
	if not Network.is_host():
		footer.append("Пинг до хоста: %d мс" % Network.get_ping_ms())
	footer.append("Игроков: %d / %d" % [Network.players.size(), Network.MAX_PLAYERS])
	_board_footer.text = "\n".join(footer)


func _cell(text: String, font_size: int, color: Color, right: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not right else Control.SIZE_FILL
	label.custom_minimum_size = Vector2(70 if right else 180, 0)
	label.clip_text = true
	return label


# --- Построение -----------------------------------------------------------

func _build() -> void:
	# Сверху по центру: [синие] таймер [красные], под ним цель.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 8.0
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 0)
	add_child(top)
	_top_bar = top

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	_blue_score = _score_box(row, TdmRules.TEAM_BLUE)
	_timer_label = _label(24, Color.WHITE)
	_timer_label.custom_minimum_size = Vector2(84, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_timer_label)
	_red_score = _score_box(row, TdmRules.TEAM_RED)

	_goal_label = _label(14, Color(0.82, 0.83, 0.8))
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_goal_label)

	_banner = _label(34, Color.WHITE)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 130.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)

	_waiting_label = _label(20, Color(1.0, 0.86, 0.6))
	_waiting_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_waiting_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_waiting_label.offset_top = 90.0
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.text = "Ожидание игроков: раунд начнётся, когда в каждой команде будет хотя бы один боец"
	_waiting_label.visible = false
	add_child(_waiting_label)

	_build_board()

	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func _score_box(row: HBoxContainer, team: int) -> Label:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var color: Color = TdmRules.TEAM_COLORS[team]
	style.bg_color = Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 0.75)
	style.border_color = color
	style.set_border_width_all(0)
	style.border_width_bottom = 3
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(150, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(panel)
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var name_label := _label(15, color)
	name_label.text = TdmRules.TEAM_NAMES[team].to_upper()
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var score := _label(30, Color.WHITE)
	score.text = "0"
	# Синие: «СИНИЕ 12», красные: «12 КРАСНЫЕ» — цифры ближе к таймеру.
	if team == TdmRules.TEAM_BLUE:
		box.add_child(name_label)
		box.add_child(score)
	else:
		box.add_child(score)
		box.add_child(name_label)
	return score


func _build_board() -> void:
	_board = CenterContainer.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	add_child(_board)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.07, 0.88)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(760, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	_board_title = _label(30, Color.WHITE)
	_board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_board_title)
	_board_subtitle = _label(16, Color(0.78, 0.8, 0.75))
	_board_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_board_subtitle)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 30)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(columns)
	for team: int in [TdmRules.TEAM_BLUE, TdmRules.TEAM_RED]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_child(column)
		var header := _label(22, TdmRules.TEAM_COLORS[team])
		column.add_child(header)
		var line := ColorRect.new()
		line.color = TdmRules.TEAM_COLORS[team]
		line.custom_minimum_size = Vector2(0, 2)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", 12)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(grid)
		_board_columns.append(column)
		_board_team_headers.append(header)
		_board_grids.append(grid)

	_board_footer = _label(14, Color(0.65, 0.67, 0.63))
	_board_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_board_footer)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_constant_override(&"outline_size", 6)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
