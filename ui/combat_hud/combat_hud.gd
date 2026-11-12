extends CanvasLayer
## Боевой HUD: прицел (раскрывается по разбросу), хитмаркер, индикатор
## урона, здоровье, патроны, лента убийств, экран смерти.
## Всё собирается кодом — сцена combat_hud.tscn содержит только этот скрипт.

const KILLFEED_LIFETIME: float = 7.0
const KILLFEED_MAX: int = 5
const DAMAGE_INDICATOR_TIME: float = 1.4

## Рисует прицел, хитмаркер и стрелки урона поверх экрана.
class Overlay extends Control:
	var hud: Node

	func _draw() -> void:
		hud.call(&"_draw_overlay", self)

var _player: Player = null
var _overlay: Overlay
var _hp_label: Label
var _hp_bar: ProgressBar
var _ammo_label: Label
var _weapon_label: Label
var _hint_label: Label
var _killfeed: VBoxContainer
var _death_panel: PanelContainer
var _death_label: Label
var _damage_flash: ColorRect
var _audio: AudioStreamPlayer

var _hitmarker_time: float = 0.0
var _hitmarker_kill: bool = false
var _hitmarker_head: bool = false
## [позиция источника, оставшееся время]
var _damage_sources: Array[Array] = []
var _killer_name: String = ""
var _respawn_at_ms: int = 0


func _ready() -> void:
	layer = 4
	_build()
	var match_node := get_parent() as Match
	if match_node != null:
		match_node.kill_announced.connect(_on_kill_announced)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) as Player
		if _player != null:
			_player.damaged.connect(_on_damaged)
			_player.hit_confirmed.connect(_on_hit_confirmed)
	var has_player: bool = _player != null
	for child: Node in get_children():
		var control := child as Control
		if control != null and control != _killfeed and control != _damage_flash:
			control.visible = has_player
	if not has_player:
		return

	_hitmarker_time = maxf(_hitmarker_time - delta, 0.0)
	for source: Array in _damage_sources:
		source[1] = float(source[1]) - delta
	_damage_sources = _damage_sources.filter(func(s: Array) -> bool: return float(s[1]) > 0.0)

	_update_labels()
	_overlay.queue_redraw()


func _update_labels() -> void:
	var weapon: WeaponController = _player.weapon
	_hp_label.text = "%d" % ceili(_player.health)
	_hp_bar.value = _player.health
	var mode: String = ""
	match weapon.weapon.fire_mode:
		WeaponData.FireMode.SEMI:
			mode = "  ·  одиночный"
		WeaponData.FireMode.BURST:
			mode = "  ·  очередь"
	_weapon_label.text = "[%d] %s%s" % [weapon.current_slot + 1, weapon.weapon.display_name, mode]
	_ammo_label.text = "%d / %d" % [weapon.ammo, weapon.reserve]
	if weapon.is_reloading:
		_hint_label.text = "перезарядка…"
	elif weapon.ammo == 0 and weapon.reserve == 0:
		_hint_label.text = "нет патронов"
	elif weapon.ammo <= weapon.weapon.mag_size / 4 and weapon.reserve > 0:
		_hint_label.text = "R — перезарядка"
	else:
		_hint_label.text = ""
	_ammo_label.modulate = Color(1, 0.45, 0.4) if weapon.ammo <= weapon.weapon.mag_size / 4 else Color.WHITE
	_hp_label.modulate = Color(1, 0.45, 0.4) if _player.health <= 30.0 else Color.WHITE

	_death_panel.visible = not _player.alive
	if not _player.alive:
		var left: float = maxf(float(_respawn_at_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
		var who: String = _killer_name if not _killer_name.is_empty() else "?"
		_death_label.text = "Вас убил: %s\nВозрождение через %d…\nB — сменить оружие" % [who, ceili(left)]


# --- События --------------------------------------------------------------

func _on_damaged(from_position: Vector3, _amount: float) -> void:
	_damage_sources.append([from_position, DAMAGE_INDICATOR_TIME])
	_damage_flash.color.a = 0.28
	var tween: Tween = _damage_flash.create_tween()
	tween.tween_property(_damage_flash, ^"color:a", 0.0, 0.5)


func _on_hit_confirmed(headshot: bool, killed: bool) -> void:
	_hitmarker_time = 0.35 if killed else 0.15
	_hitmarker_kill = killed
	_hitmarker_head = headshot
	_audio.stream = ProcSounds.get_sound(&"headshot" if headshot or killed else &"hit")
	_audio.play()


func _on_kill_announced(killer_id: int, killer_name: String, killer_team: int, victim_id: int,
		victim_name: String, victim_team: int, headshot: bool) -> void:
	var my_id: int = multiplayer.get_unique_id()
	if victim_id == my_id:
		_killer_name = killer_name
		_respawn_at_ms = Time.get_ticks_msec() + int(Match.RESPAWN_DELAY * 1000.0)
	# Имена цветом команд; строка, где участвуем мы, — на тёмной подложке.
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.scroll_active = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override(&"normal_font_size", 17)
	line.add_theme_constant_override(&"outline_size", 5)
	line.add_theme_color_override(&"font_outline_color", Color.BLACK)
	line.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.text = "%s  [color=#d8d8d0][АК%s][/color]  %s" % [
		_colored_name(killer_name, killer_team, killer_id == my_id),
		" ✚голова" if headshot else "",
		_colored_name(victim_name, victim_team, victim_id == my_id)]
	if killer_id == my_id or victim_id == my_id:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.35)
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		line.add_theme_stylebox_override(&"normal", style)
	var label: Control = line
	_killfeed.add_child(label)
	while _killfeed.get_child_count() > KILLFEED_MAX:
		_killfeed.get_child(0).free()
	var tween: Tween = label.create_tween()
	tween.tween_interval(KILLFEED_LIFETIME)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _colored_name(player_name: String, team: int, is_me: bool) -> String:
	var color: Color = TdmRules.TEAM_COLORS[clampi(team, 0, 2)]
	var safe: String = player_name.replace("[", "(").replace("]", ")")
	var text: String = "[color=#%s]%s[/color]" % [color.to_html(false), safe]
	return "[b]%s[/b]" % text if is_me else text


# --- Рисование ------------------------------------------------------------

func _draw_overlay(canvas: Control) -> void:
	if _player == null or not _player.alive:
		return
	var center: Vector2 = canvas.size * 0.5
	var weapon: WeaponController = _player.weapon
	var camera: Camera3D = canvas.get_viewport().get_camera_3d()

	# Оптика: чёрное поле вокруг круга и тонкое перекрестие.
	if weapon.is_scoped():
		_draw_scope(canvas, center)
	# Прицел.
	elif weapon.aim_amount > 0.6:
		canvas.draw_circle(center, 1.6, Color(1, 1, 1, 0.9))
	elif not _player.is_sprinting and not weapon.is_reloading and camera != null:
		var spread: float = deg_to_rad(weapon.get_current_spread())
		var half_fov: float = deg_to_rad(camera.fov * 0.5)
		var gap: float = clampf(tan(spread) / tan(half_fov) * center.y, 3.0, 120.0)
		var length: float = 9.0
		var color := Color(1, 1, 1, 0.9)
		var shadow := Color(0, 0, 0, 0.5)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = center + dir * gap
			var b: Vector2 = center + dir * (gap + length)
			canvas.draw_line(a + Vector2.ONE, b + Vector2.ONE, shadow, 2.0)
			canvas.draw_line(a, b, color, 2.0)
		canvas.draw_rect(Rect2(center - Vector2.ONE, Vector2(2, 2)), color)

	# Хитмаркер.
	if _hitmarker_time > 0.0:
		var color: Color = Color(1.0, 0.25, 0.2) if _hitmarker_kill else (
				Color(1.0, 0.85, 0.3) if _hitmarker_head else Color.WHITE)
		var size: float = 11.0 if _hitmarker_kill else 8.0
		for diag: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = diag.normalized()
			canvas.draw_line(center + n * 6.0, center + n * (6.0 + size), color, 2.5)

	# Откуда стреляли.
	if camera != null:
		var inverse: Transform3D = camera.global_transform.affine_inverse()
		for source: Array in _damage_sources:
			var local: Vector3 = inverse * (source[0] as Vector3)
			var angle: float = atan2(local.x, -local.z)
			var alpha: float = clampf(float(source[1]) / DAMAGE_INDICATOR_TIME, 0.0, 1.0)
			var color := Color(0.9, 0.12, 0.08, 0.85 * alpha)
			var dir := Vector2(sin(angle), -cos(angle))
			var side := Vector2(-dir.y, dir.x)
			var tip: Vector2 = center + dir * 150.0
			var base: Vector2 = center + dir * 120.0
			canvas.draw_colored_polygon(PackedVector2Array([
				tip, base + side * 22.0, base - side * 22.0]), color)


func _draw_scope(canvas: Control, center: Vector2) -> void:
	var radius: float = canvas.size.y * 0.46
	var black := Color(0.0, 0.0, 0.0, 1.0)
	# Поле вокруг круга — кольцом из толстых дуг, плюс прямоугольники по бокам.
	canvas.draw_arc(center, radius + canvas.size.y * 0.5, 0.0, TAU, 96, black, canvas.size.y, true)
	canvas.draw_rect(Rect2(0.0, 0.0, center.x - radius + 1.0, canvas.size.y), black)
	canvas.draw_rect(Rect2(center.x + radius - 1.0, 0.0, canvas.size.x, canvas.size.y), black)
	canvas.draw_arc(center, radius, 0.0, TAU, 96, Color(0.05, 0.05, 0.05), 6.0, true)
	var line := Color(0.0, 0.0, 0.0, 0.85)
	canvas.draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), line, 1.5)
	canvas.draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), line, 1.5)
	# Толстые «пеньки» к краям, как у настоящих прицелов.
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		canvas.draw_line(center + dir * radius * 0.45, center + dir * radius, line, 5.0)
	canvas.draw_circle(center, 1.5, Color(0.8, 0.1, 0.1))


# --- Построение интерфейса ------------------------------------------------

func _build() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_damage_flash)

	_overlay = Overlay.new()
	_overlay.hud = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# Справа внизу: оружие, патроны, здоровье.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -260.0
	box.offset_top = -150.0
	box.offset_right = -24.0
	box.offset_bottom = -20.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_hint_label = _label(16, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_hint_label)
	_weapon_label = _label(16, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_weapon_label)
	_ammo_label = _label(34, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_ammo_label)

	var hp_row := HBoxContainer.new()
	hp_row.alignment = BoxContainer.ALIGNMENT_END
	hp_row.add_theme_constant_override(&"separation", 10)
	box.add_child(hp_row)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = Player.MAX_HEALTH
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(150, 12)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.88, 0.82)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	_hp_bar.add_theme_stylebox_override(&"fill", fill)
	_hp_bar.add_theme_stylebox_override(&"background", back)
	hp_row.add_child(_hp_bar)
	_hp_label = _label(26, HORIZONTAL_ALIGNMENT_RIGHT)
	_hp_label.custom_minimum_size = Vector2(50, 0)
	hp_row.add_child(_hp_label)

	# Справа вверху: лента убийств.
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.offset_left = -520.0
	_killfeed.offset_top = 84.0  # ниже счёта команд (TdmHud)
	_killfeed.offset_right = -18.0
	_killfeed.offset_bottom = 270.0
	_killfeed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_killfeed)

	# По центру: экран смерти.
	_death_panel = PanelContainer.new()
	_death_panel.set_anchors_preset(Control.PRESET_CENTER)
	_death_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_panel.offset_top = 60.0
	_death_panel.offset_bottom = 60.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.05, 0.75)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_death_panel.add_theme_stylebox_override(&"panel", style)
	_death_panel.visible = false
	add_child(_death_panel)
	_death_label = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_death_panel.add_child(_death_label)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_constant_override(&"outline_size", 6)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
