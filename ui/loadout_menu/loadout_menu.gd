extends CanvasLayer
## Меню снаряжения: основной ствол + пистолет. Открывается по B, из меню Esc
## и с экрана выбора команды. Выбор сохраняется на ПК игрока
## (WeaponCatalog, user://loadout.cfg) и применяется при следующем появлении;
## если боец ещё не появлялся — сразу при появлении.
## Всё собирается кодом — сцена loadout_menu.tscn содержит только этот скрипт.

const GROUP: StringName = &"loadout_menu"
const STAT_NAMES: Array[String] = ["Урон", "Скорострельность", "Дальность", "Точность", "Управляемость"]

var _buttons: Dictionary = {}  # StringName id → Button
var _preview: WeaponData
var _title: Label
var _category: Label
var _description: Label
var _numbers: Label
var _bars: Array[ProgressBar] = []
var _note: Label


func _ready() -> void:
	layer = 16
	add_to_group(GROUP)
	_build()
	visible = false


func open() -> void:
	WeaponCatalog.load_loadout()
	_preview = WeaponCatalog.get_by_id(WeaponCatalog.primary_id)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if not _is_other_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"loadout"):
		# Из меню паузы и выбора команды открываем кнопкой, а не клавишей.
		if visible or not _is_other_menu_open():
			toggle()
			get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"release_mouse"):
		close()
		get_viewport().set_input_as_handled()


func _choose(weapon: WeaponData) -> void:
	WeaponCatalog.set_choice(weapon)
	_preview = weapon
	_refresh()


func _refresh() -> void:
	for weapon_id: StringName in _buttons:
		var button: Button = _buttons[weapon_id]
		var chosen: bool = weapon_id == WeaponCatalog.primary_id or weapon_id == WeaponCatalog.secondary_id
		button.button_pressed = chosen
		var weapon: WeaponData = WeaponCatalog.get_by_id(weapon_id)
		button.text = "%s%s\n%s" % ["✔ " if chosen else "", weapon.display_name,
				WeaponData.CATEGORY_NAMES[weapon.category]]
		button.modulate = Color(1.0, 0.93, 0.7) if chosen else Color.WHITE
	if _preview == null:
		return
	_title.text = _preview.display_name
	_category.text = WeaponData.CATEGORY_NAMES[_preview.category] + "  ·  " + _fire_mode_text(_preview)
	_description.text = _preview.description
	var damage: String = "%d" % roundi(_preview.damage_close)
	if _preview.pellets > 1:
		damage = "%d × %d дробинок" % [roundi(_preview.damage_close), _preview.pellets]
	_numbers.text = "Урон: %s (вдали %d)   ·   %d выстр/мин   ·   магазин %d + %d" % [
		damage, roundi(_preview.damage_far), roundi(_preview.fire_rate_rpm), _preview.mag_size, _preview.reserve_ammo]
	var stats: Array[float] = get_stats(_preview)
	for i: int in _bars.size():
		_bars[i].value = stats[i]

	var player := get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) as Player
	if player != null and player.alive:
		_note.text = "Новое снаряжение — при следующем появлении."
	else:
		_note.text = "Снаряжение выдаётся при появлении."


## Оценки 0..100 для полосок (только для сравнения стволов между собой).
static func get_stats(weapon: WeaponData) -> Array[float]:
	var per_shot: float = weapon.damage_close * maxf(float(weapon.pellets), 1.0) * (0.6 if weapon.pellets > 1 else 1.0)
	var damage: float = clampf(per_shot / 100.0 * 100.0, 5.0, 100.0)
	var rate: float = clampf(weapon.fire_rate_rpm / 1000.0 * 100.0, 5.0, 100.0)
	var reach: float = clampf((weapon.falloff_start + weapon.falloff_end) / 400.0 * 100.0, 5.0, 100.0)
	var accuracy: float = clampf(100.0 - weapon.spread_hip * 18.0 - weapon.spread_ads * 60.0, 5.0, 100.0)
	var control: float = clampf(100.0 - weapon.recoil_vertical * 30.0 - weapon.recoil_horizontal * 40.0, 5.0, 100.0)
	var result: Array[float] = [damage, rate, reach, accuracy, control]
	return result


static func _fire_mode_text(weapon: WeaponData) -> String:
	match weapon.fire_mode:
		WeaponData.FireMode.AUTO:
			return "автоматический огонь"
		WeaponData.FireMode.BURST:
			return "очередь по %d" % weapon.burst_count
		_:
			return "одиночный огонь"


func _is_other_menu_open() -> bool:
	for group: StringName in [&"team_select"]:
		var node := get_tree().get_first_node_in_group(group) as CanvasLayer
		if node != null and node.visible:
			return true
	var pause := get_parent().get_node_or_null(^"PauseMenu") as CanvasLayer
	return pause != null and pause.visible


# --- Построение -----------------------------------------------------------

func _build() -> void:
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
	style.bg_color = Color(0.1, 0.11, 0.1, 0.96)
	style.set_content_margin_all(22.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "СНАРЯЖЕНИЕ"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(&"font_size", 28)
	vbox.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 20)
	vbox.add_child(row)

	row.add_child(_build_column("ОСНОВНОЕ  [1]", WeaponData.Slot.PRIMARY))
	row.add_child(_build_column("ПИСТОЛЕТ  [2]", WeaponData.Slot.SECONDARY))
	row.add_child(_build_details())

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override(&"font_color", Color(0.75, 0.77, 0.7))
	vbox.add_child(_note)

	var done := Button.new()
	done.text = "Готово (B / Esc)"
	done.custom_minimum_size = Vector2(0, 38)
	done.pressed.connect(close)
	vbox.add_child(done)


func _build_column(title: String, slot: WeaponData.Slot) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	column.custom_minimum_size = Vector2(220, 0)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override(&"font_color", Color(0.8, 0.82, 0.74))
	column.add_child(label)
	var group := ButtonGroup.new()
	for weapon: WeaponData in WeaponCatalog.list_slot(slot):
		var button := Button.new()
		button.text = "%s\n%s" % [weapon.display_name, WeaponData.CATEGORY_NAMES[weapon.category]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(220, 52)
		button.pressed.connect(_choose.bind(weapon))
		button.mouse_entered.connect(func() -> void:
			_preview = weapon
			_refresh())
		column.add_child(button)
		_buttons[weapon.id] = button
	return column


func _build_details() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override(&"separation", 6)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 24)
	box.add_child(_title)
	_category = Label.new()
	_category.add_theme_color_override(&"font_color", Color(0.75, 0.77, 0.7))
	box.add_child(_category)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(380, 48)
	box.add_child(_description)
	for stat_name: String in STAT_NAMES:
		var label := Label.new()
		label.text = stat_name
		label.add_theme_font_size_override(&"font_size", 14)
		box.add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(380, 10)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.82, 0.78, 0.55)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0, 0, 0, 0.5)
		bar.add_theme_stylebox_override(&"fill", fill)
		bar.add_theme_stylebox_override(&"background", back)
		box.add_child(bar)
		_bars.append(bar)
	_numbers = Label.new()
	_numbers.add_theme_font_size_override(&"font_size", 14)
	_numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_numbers.custom_minimum_size = Vector2(380, 0)
	box.add_child(_numbers)
	return box
