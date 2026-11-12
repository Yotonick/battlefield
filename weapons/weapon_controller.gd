class_name WeaponController
extends Node
## Оружие в руках бойца: два слота (основной + пистолет), патроны, стрельба,
## перезарядка, прицел, разброс, отдача, смена оружия.
##
## Логика работает только у владельца бойца (вызывается из Player._simulate
## каждый тик физики). Выстрел уходит через Player.fire_shot → хост.
## У чужих бойцов этот узел только показывает модель, вспышку и звук;
## какой ствол у них в руках — по Player.net_weapon (номер в WeaponCatalog).

signal ammo_changed
signal shot_fired
## Сменился ствол в руках (у владельца).
signal weapon_changed

## Слот снаряжения: ствол и его патроны (патроны помнятся при смене оружия).
class Slot:
	var data: WeaponData
	var ammo: int = 0
	var reserve: int = 0

	func _init(weapon_data: WeaponData) -> void:
		data = weapon_data
		ammo = weapon_data.mag_size
		reserve = weapon_data.reserve_ammo

const SPRINT_POSITION := Vector3(0.12, -0.24, -0.28)
const SPRINT_ROTATION := Vector3(-0.25, 0.7, 0.15)
## Положение «в мире» (у головы чужого бойца).
const WORLD_POSITION := Vector3(0.2, -0.28, -0.05)
## Скорость возврата подброса камеры, градусов в секунду.
const RECOIL_RECOVERY_SPEED: float = 10.0
## Нажатие спуска «запоминается» на это время (одиночный огонь, помпа).
const TRIGGER_BUFFER: float = 0.2

## Ствол в руках. Присвоение заменяет ствол в текущем слоте (для тестов).
var weapon: WeaponData:
	set(value):
		weapon = value
		if not slots.is_empty():
			slots[current_slot].data = value
var slots: Array[Slot] = []
var current_slot: int = 0
var ammo: int:
	get:
		return slots[current_slot].ammo if not slots.is_empty() else 0
	set(value):
		if not slots.is_empty():
			slots[current_slot].ammo = value
var reserve: int:
	get:
		return slots[current_slot].reserve if not slots.is_empty() else 0
	set(value):
		if not slots.is_empty():
			slots[current_slot].reserve = value
var is_reloading: bool = false
## Идёт смена оружия (ствол достаётся).
var is_switching: bool = false
## 0 — от бедра, 1 — в прицеле.
var aim_amount: float = 0.0
var is_aiming: bool = false
var is_fire_held: bool = false

var _player: Player
var _camera: Camera3D
var _head: Node3D
var _is_local: bool = false
var _cooldown: float = 0.0
var _extra_spread: float = 0.0
var _since_sprint: float = 1.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _reload_was_empty: bool = false
var _reload_sound_step: int = 0
var _recoil_to_recover: float = 0.0
var _vm_kick: float = 0.0
var _vm_sprint: float = 0.0
var _switch_left: float = 0.0
var _switch_total: float = 0.0
var _trigger_buffer: float = 0.0
var _burst_left: int = 0

var _viewmodel: GunView
## Руки от первого лица (только у своего бойца).
var _arms: FirstPersonArms
var _world_gun: GunView
## Номер в каталоге ствола, который сейчас показан «в мире».
var _world_index: int = -1
var _audio_local: AudioStreamPlayer
var _audio_world: AudioStreamPlayer3D


func setup(player: Player, camera: Camera3D, head: Node3D, is_local: bool) -> void:
	_player = player
	_camera = camera
	_head = head
	_is_local = is_local

	_audio_world = AudioStreamPlayer3D.new()
	_audio_world.name = "GunAudio"
	_audio_world.max_distance = 400.0
	_audio_world.unit_size = 12.0
	_audio_world.max_polyphony = 4
	head.add_child(_audio_world)

	if is_local:
		_audio_local = AudioStreamPlayer.new()
		_audio_local.name = "LocalGunAudio"
		_audio_local.max_polyphony = 6
		add_child(_audio_local)
		_arms = FirstPersonArms.new()
		_arms.visible = _player.alive
		camera.add_child(_arms)
		equip_loadout()
	else:
		_show_world_weapon(maxi(_player.net_weapon, 0))


## Владелец: взять снаряжение из меню (при появлении и возрождении).
func equip_loadout() -> void:
	slots.clear()
	for data: WeaponData in WeaponCatalog.get_loadout():
		slots.append(Slot.new(data))
	_select_slot(0, false)


## Совместимость: «полные патроны» = заново выдать снаряжение.
func reset_ammo() -> void:
	equip_loadout()


func _select_slot(index: int, animate: bool) -> void:
	current_slot = clampi(index, 0, slots.size() - 1)
	weapon = slots[current_slot].data
	is_reloading = false
	_extra_spread = 0.0
	_cooldown = 0.0
	_burst_left = 0
	_trigger_buffer = 0.0
	aim_amount = 0.0
	is_aiming = false
	is_fire_held = false
	_switch_total = weapon.draw_time if animate else 0.0
	_switch_left = _switch_total
	is_switching = animate
	_player.net_weapon = WeaponCatalog.get_index(weapon.id)
	_rebuild_viewmodel()
	_show_world_weapon(_player.net_weapon)
	if animate:
		_play_local(&"mag")
	weapon_changed.emit()
	ammo_changed.emit()


func _rebuild_viewmodel() -> void:
	if not _is_local:
		return
	if _viewmodel != null:
		_viewmodel.queue_free()
	_viewmodel = GunView.new(weapon)
	_viewmodel.set_first_person()
	_viewmodel.position = _viewmodel.hip_position
	_viewmodel.rotation = _viewmodel.hip_rotation
	_viewmodel.visible = _player.alive
	_camera.add_child(_viewmodel)


## Модель «в мире»: у чужих — что в руках у владельца, у себя — только тень.
func _show_world_weapon(index: int) -> void:
	if index == _world_index:
		return
	var data: WeaponData = WeaponCatalog.get_by_index(index)
	if data == null:
		return
	_world_index = index
	if _world_gun != null:
		_world_gun.queue_free()
	_world_gun = GunView.new(data)
	_world_gun.position = WORLD_POSITION
	_world_gun.visible = _player.alive
	if _is_local:
		_world_gun.set_shadow_only(true)
	_head.add_child(_world_gun)


## Мешает ли оружие бегу (стреляем или целимся).
func blocks_sprint() -> bool:
	return is_fire_held or is_aiming


## Текущий разброс в градусах (для пули и для прицела на экране).
func get_current_spread() -> float:
	var base: float = lerpf(weapon.spread_hip, weapon.spread_ads, aim_amount)
	var speed_ratio: float = clampf(_player.get_horizontal_speed() / _player.walk_speed, 0.0, 1.0)
	base *= lerpf(1.0, weapon.spread_move_multiplier, speed_ratio)
	if _player.stance == Player.Stance.CROUCH:
		base *= weapon.spread_crouch_multiplier
	if not _player.is_on_floor():
		base = maxf(base, weapon.spread_air)
	return base + _extra_spread * lerpf(1.0, 0.5, aim_amount)


## Смотрим в оптику (модель скрыта, на экране — круг прицела).
func is_scoped() -> bool:
	return weapon != null and weapon.has_scope and aim_amount > 0.85


# --- Логика владельца (тик физики) ---------------------------------------

func tick(input: Player.InputState, delta: float) -> void:
	if slots.is_empty():
		return
	var can_act: bool = _player.alive
	if can_act:
		_handle_switch_input(input)
	_update_switch(delta)

	is_fire_held = can_act and input.fire_held
	_cooldown = maxf(_cooldown - delta, -1.0)
	_extra_spread = maxf(_extra_spread - weapon.spread_recovery * delta, 0.0)
	_trigger_buffer = maxf(_trigger_buffer - delta, 0.0)
	if can_act and input.fire_pressed:
		_trigger_buffer = TRIGGER_BUFFER

	if _player.is_sprinting:
		_since_sprint = 0.0
	else:
		_since_sprint += delta

	_update_reload(delta)
	if can_act and input.reload_pressed and not is_switching:
		start_reload()

	is_aiming = can_act and input.aim_held and not is_reloading and not is_switching \
			and not _player.is_sprinting
	var aim_step: float = delta / maxf(weapon.ads_time, 0.01)
	aim_amount = move_toward(aim_amount, 1.0 if is_aiming else 0.0, aim_step)

	var can_fire: bool = can_act and not is_reloading and not is_switching \
			and _since_sprint >= weapon.sprint_to_fire_time
	if can_fire:
		_update_trigger(input)
	elif is_reloading or is_switching:
		_burst_left = 0

	if not is_fire_held and _burst_left == 0 and _cooldown < 0.0:
		_cooldown = 0.0

	# Камера сама немного опускается после очереди.
	if not is_fire_held and _recoil_to_recover > 0.0:
		var step: float = minf(_recoil_to_recover, RECOIL_RECOVERY_SPEED * delta)
		_recoil_to_recover -= step
		_player.add_view_kick(-deg_to_rad(step), 0.0)


## Спуск: автомат — пока зажат; одиночный — по нажатию; очередь — N выстрелов.
func _update_trigger(input: Player.InputState) -> void:
	if ammo <= 0:
		_burst_left = 0
		if input.fire_pressed:
			_play_local(&"click")
			start_reload()
		return
	match weapon.fire_mode:
		WeaponData.FireMode.AUTO:
			if is_fire_held:
				# Несколько выстрелов за тик возможны при высокой скорострельности.
				while _cooldown <= 0.0 and ammo > 0:
					_shoot()
					_cooldown += weapon.get_shot_interval()
		WeaponData.FireMode.SEMI:
			if _trigger_buffer > 0.0 and _cooldown <= 0.0:
				_trigger_buffer = 0.0
				_shoot()
				_cooldown = weapon.get_shot_interval()
		WeaponData.FireMode.BURST:
			if _burst_left == 0 and _trigger_buffer > 0.0 and _cooldown <= 0.0:
				_trigger_buffer = 0.0
				_burst_left = weapon.burst_count
			while _burst_left > 0 and _cooldown <= 0.0 and ammo > 0:
				_shoot()
				_burst_left -= 1
				_cooldown += weapon.get_shot_interval()
				if _burst_left == 0:
					_cooldown += weapon.burst_delay
			if ammo <= 0:
				_burst_left = 0


func _handle_switch_input(input: Player.InputState) -> void:
	if input.switch_to < 0 or slots.size() < 2:
		return
	var target: int = input.switch_to
	if target == Player.SWITCH_NEXT:
		target = (current_slot + 1) % slots.size()
	if target == current_slot or target >= slots.size():
		return
	_select_slot(target, true)


func _update_switch(delta: float) -> void:
	if not is_switching:
		return
	_switch_left -= delta
	if _switch_left <= 0.0:
		_switch_left = 0.0
		is_switching = false


func start_reload() -> void:
	if is_reloading or is_switching or ammo >= weapon.mag_size or reserve <= 0:
		return
	is_reloading = true
	_burst_left = 0
	_reload_was_empty = ammo == 0
	_reload_total = weapon.reload_empty_time if _reload_was_empty else weapon.reload_time
	_reload_left = _reload_total
	_reload_sound_step = 0
	ammo_changed.emit()


func cancel_reload() -> void:
	is_reloading = false
	_burst_left = 0
	ammo_changed.emit()


## 0..1 — сколько перезарядки прошло.
func get_reload_progress() -> float:
	if not is_reloading or _reload_total <= 0.0:
		return 0.0
	return 1.0 - _reload_left / _reload_total


func _update_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_left -= delta
	var progress: float = get_reload_progress()
	# Звуки: магазин вынут, вставлен, (пустой) затвор.
	if _reload_sound_step == 0 and progress > 0.2:
		_reload_sound_step = 1
		_play_local(&"mag")
	elif _reload_sound_step == 1 and progress > 0.6:
		_reload_sound_step = 2
		_play_local(&"mag")
	elif _reload_sound_step == 2 and _reload_was_empty and progress > 0.85:
		_reload_sound_step = 3
		_play_local(&"click")
	if _reload_left <= 0.0:
		var need: int = weapon.mag_size - ammo
		var taken: int = mini(need, reserve)
		ammo += taken
		reserve -= taken
		is_reloading = false
		ammo_changed.emit()


func _shoot() -> void:
	var spread: float = deg_to_rad(get_current_spread())
	var basis: Basis = _player.get_view_basis()
	var main_dir: Vector3 = _random_cone(spread)
	var directions := PackedVector3Array()
	if weapon.pellets <= 1:
		directions.append((basis * main_dir).normalized())
	else:
		# Дробь: облако вокруг направления «обычного» выстрела.
		var aim_basis := Basis.looking_at(main_dir, Vector3.UP)
		var pellet_cone: float = deg_to_rad(weapon.pellet_spread)
		for i: int in weapon.pellets:
			directions.append((basis * (aim_basis * _random_cone(pellet_cone))).normalized())
	_player.fire_shot(_player.get_eye_position(), directions, WeaponCatalog.get_index(weapon.id))

	ammo -= 1
	_extra_spread = minf(_extra_spread + weapon.spread_per_shot, weapon.spread_max_extra)
	var recoil_mult: float = lerpf(1.0, weapon.recoil_ads_multiplier, aim_amount)
	var vertical: float = weapon.recoil_vertical * recoil_mult * randf_range(0.85, 1.15)
	var horizontal: float = weapon.recoil_horizontal * recoil_mult * randf_range(-1.0, 1.0)
	_player.add_view_kick(deg_to_rad(vertical), deg_to_rad(horizontal))
	_recoil_to_recover += vertical * weapon.recoil_recovery
	_vm_kick = 1.0
	if _viewmodel != null:
		_viewmodel.flash()
	_play_local(&"shot")
	shot_fired.emit()
	ammo_changed.emit()


## Случайное направление внутри конуса (вперёд — −Z).
static func _random_cone(angle: float) -> Vector3:
	var radius: float = tan(angle) * sqrt(randf())
	var phi: float = randf() * TAU
	return Vector3(radius * cos(phi), radius * sin(phi), -1.0)


func _play_local(sound: StringName) -> void:
	if _audio_local == null:
		return
	_audio_local.stream = ProcSounds.get_sound(sound)
	_audio_local.pitch_scale = _shot_pitch(weapon) if sound == &"shot" else 1.0
	_audio_local.play()


## Пока своих звуков у стволов нет (шаг 2): различаем высотой тона.
static func _shot_pitch(data: WeaponData) -> float:
	if data == null:
		return 1.0
	match data.category:
		WeaponData.Category.SMG:
			return 1.25
		WeaponData.Category.PISTOL:
			return 1.4
		WeaponData.Category.SHOTGUN:
			return 0.7
		WeaponData.Category.SNIPER, WeaponData.Category.BATTLE:
			return 0.8
		_:
			return 1.0


# --- Вид ------------------------------------------------------------------

## Выстрел чужого бойца: вспышка и звук в мире.
func play_remote_shot(weapon_index: int) -> void:
	_show_world_weapon(weapon_index)
	if _world_gun != null:
		_world_gun.flash()
	var listener: Camera3D = _player.get_viewport().get_camera_3d()
	var far: bool = listener != null and listener.global_position.distance_to(_player.global_position) > 60.0
	_audio_world.stream = ProcSounds.get_sound(&"shot_far" if far else &"shot")
	_audio_world.pitch_scale = _shot_pitch(WeaponCatalog.get_by_index(weapon_index))
	_audio_world.play()


func set_world_gun_visible(value: bool) -> void:
	if _world_gun != null:
		_world_gun.visible = value
	if _viewmodel != null:
		_viewmodel.visible = value
	if _arms != null:
		_arms.visible = value


func _process(delta: float) -> void:
	if not _is_local:
		# Чужой боец сменил ствол.
		if _player.net_weapon != _world_index and _player.net_weapon >= 0:
			_show_world_weapon(_player.net_weapon)
		return
	if _viewmodel == null:
		return
	_vm_kick = lerpf(_vm_kick, 0.0, 1.0 - exp(-18.0 * delta))
	_vm_sprint = lerpf(_vm_sprint, 1.0 if _player.is_sprinting else 0.0, 1.0 - exp(-10.0 * delta))

	var aim_t: float = _ease(aim_amount)
	var pos: Vector3 = _viewmodel.hip_position.lerp(_viewmodel.ads_position, aim_t)
	pos = pos.lerp(SPRINT_POSITION, _vm_sprint)
	pos.z += 0.045 * _vm_kick * lerpf(1.0, 0.5, aim_amount)
	var kick_pitch: float = 0.06 if weapon.recoil_vertical < 1.5 else 0.2
	var hip_rot: Vector3 = _viewmodel.hip_rotation.lerp(_viewmodel.ads_rotation, aim_t)
	var rot := Vector3(kick_pitch * _vm_kick, 0.0, 0.0) + hip_rot
	rot = rot.lerp(SPRINT_ROTATION, _vm_sprint)
	if is_reloading:
		var dip: float = sin(PI * get_reload_progress())
		rot.x -= 0.35 * dip
		rot.z += 0.45 * dip
		pos.y -= 0.03 * dip
	if is_switching and _switch_total > 0.0:
		# Ствол поднимается снизу.
		var t: float = _switch_left / _switch_total
		pos.y -= 0.25 * t * t
		rot.x -= 0.6 * t * t
	_viewmodel.position = pos
	_viewmodel.rotation = rot
	_viewmodel.visible = _player.alive and not is_scoped()
	if _arms != null:
		_arms.visible = _viewmodel.visible
		if _arms.visible:
			_arms.solve(_viewmodel, delta)


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
