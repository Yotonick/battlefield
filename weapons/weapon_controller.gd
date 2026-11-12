class_name WeaponController
extends Node
## Оружие в руках бойца: патроны, стрельба, перезарядка, прицел, разброс, отдача.
##
## Логика работает только у владельца бойца (вызывается из Player._simulate
## каждый тик физики). Выстрел уходит через Player.fire_shot → хост.
## У чужих бойцов этот узел только показывает модель, вспышку и звук.

signal ammo_changed
signal shot_fired

@export var weapon: WeaponData = preload("res://weapons/rifle_ak.tres")

const HIP_POSITION := Vector3(0.16, -0.19, -0.3)
const ADS_POSITION := Vector3(0.0, 0.0, -0.33)
const SPRINT_POSITION := Vector3(0.12, -0.24, -0.28)
const SPRINT_ROTATION := Vector3(-0.25, 0.7, 0.15)
## Скорость возврата подброса камеры, градусов в секунду.
const RECOIL_RECOVERY_SPEED: float = 10.0

var ammo: int = 0
var reserve: int = 0
var is_reloading: bool = false
## 0 — от бедра, 1 — в прицеле.
var aim_amount: float = 0.0
var is_aiming: bool = false
var is_fire_held: bool = false

var _player: Player
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

var _viewmodel: GreyboxGun
var _world_gun: GreyboxGun
var _audio_local: AudioStreamPlayer
var _audio_world: AudioStreamPlayer3D


func setup(player: Player, camera: Camera3D, head: Node3D, is_local: bool) -> void:
	_player = player
	_is_local = is_local
	reset_ammo()

	_world_gun = GreyboxGun.new()
	_world_gun.position = Vector3(0.2, -0.28, -0.22)
	head.add_child(_world_gun)

	_audio_world = AudioStreamPlayer3D.new()
	_audio_world.name = "GunAudio"
	_audio_world.max_distance = 400.0
	_audio_world.unit_size = 12.0
	_audio_world.max_polyphony = 4
	head.add_child(_audio_world)

	if is_local:
		_world_gun.set_shadow_only(true)
		_viewmodel = GreyboxGun.new()
		_viewmodel.set_first_person()
		_viewmodel.position = HIP_POSITION
		camera.add_child(_viewmodel)
		_audio_local = AudioStreamPlayer.new()
		_audio_local.name = "LocalGunAudio"
		_audio_local.max_polyphony = 6
		add_child(_audio_local)


func reset_ammo() -> void:
	ammo = weapon.mag_size
	reserve = weapon.reserve_ammo
	is_reloading = false
	_extra_spread = 0.0
	_cooldown = 0.0
	aim_amount = 0.0
	is_aiming = false
	is_fire_held = false
	ammo_changed.emit()


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


# --- Логика владельца (тик физики) ---------------------------------------

func tick(input: Player.InputState, delta: float) -> void:
	var can_act: bool = _player.alive
	is_fire_held = can_act and input.fire_held
	_cooldown = maxf(_cooldown - delta, -1.0)
	_extra_spread = maxf(_extra_spread - weapon.spread_recovery * delta, 0.0)

	if _player.is_sprinting:
		_since_sprint = 0.0
	else:
		_since_sprint += delta

	_update_reload(delta)
	if can_act and input.reload_pressed:
		start_reload()

	is_aiming = can_act and input.aim_held and not is_reloading and not _player.is_sprinting
	var aim_step: float = delta / maxf(weapon.ads_time, 0.01)
	aim_amount = move_toward(aim_amount, 1.0 if is_aiming else 0.0, aim_step)

	if is_fire_held and not is_reloading:
		if ammo <= 0:
			if input.fire_pressed:
				_play_local(&"click")
				start_reload()
		elif _since_sprint >= weapon.sprint_to_fire_time:
			# Несколько выстрелов за тик возможны при высокой скорострельности.
			while _cooldown <= 0.0 and ammo > 0:
				_shoot()
				_cooldown += weapon.get_shot_interval()
	if not is_fire_held and _cooldown < 0.0:
		_cooldown = 0.0

	# Камера сама немного опускается после очереди.
	if not is_fire_held and _recoil_to_recover > 0.0:
		var step: float = minf(_recoil_to_recover, RECOIL_RECOVERY_SPEED * delta)
		_recoil_to_recover -= step
		_player.add_view_kick(-deg_to_rad(step), 0.0)


func start_reload() -> void:
	if is_reloading or ammo >= weapon.mag_size or reserve <= 0:
		return
	is_reloading = true
	_reload_was_empty = ammo == 0
	_reload_total = weapon.reload_empty_time if _reload_was_empty else weapon.reload_time
	_reload_left = _reload_total
	_reload_sound_step = 0
	ammo_changed.emit()


func cancel_reload() -> void:
	is_reloading = false
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
	var radius: float = tan(spread) * sqrt(randf())
	var phi: float = randf() * TAU
	var local_dir := Vector3(radius * cos(phi), radius * sin(phi), -1.0)
	var direction: Vector3 = (_player.get_view_basis() * local_dir).normalized()
	_player.fire_shot(_player.get_eye_position(), direction)

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


func _play_local(sound: StringName) -> void:
	if _audio_local == null:
		return
	_audio_local.stream = ProcSounds.get_sound(sound)
	_audio_local.play()


# --- Вид ------------------------------------------------------------------

## Выстрел чужого бойца: вспышка и звук в мире.
func play_remote_shot() -> void:
	_world_gun.flash()
	var listener: Camera3D = _player.get_viewport().get_camera_3d()
	var far: bool = listener != null and listener.global_position.distance_to(_player.global_position) > 60.0
	_audio_world.stream = ProcSounds.get_sound(&"shot_far" if far else &"shot")
	_audio_world.play()


func set_world_gun_visible(value: bool) -> void:
	if _world_gun != null:
		_world_gun.visible = value
	if _viewmodel != null:
		_viewmodel.visible = value


func _process(delta: float) -> void:
	if _viewmodel == null:
		return
	_vm_kick = lerpf(_vm_kick, 0.0, 1.0 - exp(-18.0 * delta))
	_vm_sprint = lerpf(_vm_sprint, 1.0 if _player.is_sprinting else 0.0, 1.0 - exp(-10.0 * delta))

	var pos: Vector3 = HIP_POSITION.lerp(ADS_POSITION, _ease(aim_amount))
	pos = pos.lerp(SPRINT_POSITION, _vm_sprint)
	pos.z += 0.045 * _vm_kick * lerpf(1.0, 0.5, aim_amount)
	var rot := Vector3(0.06 * _vm_kick, 0.0, 0.0)
	rot = rot.lerp(SPRINT_ROTATION, _vm_sprint)
	if is_reloading:
		var dip: float = sin(PI * get_reload_progress())
		rot.x -= 0.35 * dip
		rot.z += 0.45 * dip
		pos.y -= 0.03 * dip
	_viewmodel.position = pos
	_viewmodel.rotation = rot


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
