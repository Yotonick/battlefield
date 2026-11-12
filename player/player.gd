class_name Player
extends CharacterBody3D
## Боец от первого лица: ходьба, бег, присед, прыжок, обзор мышью.
##
## Сеть (решение 17, вариант А): бойцом управляет только его владелец
## (multiplayer authority = peer id игрока). Владелец симулирует движение и
## раз в 1/30 с рассылает состояние через MultiplayerSynchronizer.
## У остальных боец — «марионетка»: снимки состояния копятся в буфере и
## проигрываются с задержкой interpolation_delay, плавно между снимками.
##
## Бой (шаг 3): здоровье, смерть и респавн решает хост. Выстрел владелец
## делает у себя (пуля для вида) и шлёт хосту; хост пускает «настоящую» пулю
## и проверяет попадание по бойцам «в прошлом» (компенсация пинга).
## Здоровье, «жив», убийства, смерти и команду хост рассылает через HostSync.
##
## Команды (шаг 4): цвет тела по команде; имя над головой видно только у
## своих (и сквозь стены); пули сквозь своих пролетают — огня по своим нет.

enum Stance { STAND, CROUCH }

## Предел наклона камеры вверх/вниз.
const PITCH_LIMIT: float = 1.5533430  # 89°
## Группа, по которой UI находит своего (локального) бойца.
const LOCAL_PLAYER_GROUP: StringName = &"local_player"
## Все бойцы (свои и чужие).
const PLAYERS_GROUP: StringName = &"players"
const MAX_HEALTH: float = 100.0
## Сколько секунд хост помнит, где был боец (для компенсации пинга).
const HISTORY_SECONDS: float = 0.6
## Больше этого пинга не компенсируем, секунд.
const MAX_REWIND: float = 0.3
## Цвет тела по команде (greybox, до настоящих моделей).
## InputState.switch_to: следующий ствол по кругу (колесо мыши).
const SWITCH_NEXT: int = 2
const TEAM_BODY_COLORS: Array[Color] = [Color(0.36, 0.42, 0.3), Color(0.3, 0.4, 0.55), Color(0.58, 0.34, 0.28)]

## Только на хосте: бойца убили.
signal killed_on_host(victim: Player, killer_id: int, headshot: bool)
## У владельца: в нас попали (откуда стреляли — для индикатора).
signal damaged(from_position: Vector3, amount: float)
## У стрелка: хост подтвердил попадание.
signal hit_confirmed(headshot: bool, killed: bool)
## На всех машинах: боец умер или ожил.
signal alive_changed(is_alive: bool)

@export_group("Скорости, м/с")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 6.8
@export var crouch_speed: float = 2.3

@export_group("Ускорения, м/с²")
## Разгон на земле.
@export var ground_accel: float = 45.0
## Торможение на земле, когда клавиши отпущены.
@export var ground_decel: float = 35.0
## Управление в воздухе (маленькое — прыжок почти не меняет траекторию).
@export var air_accel: float = 8.0

@export_group("Прыжок")
## Высота прыжка в метрах (по ногам).
@export var jump_height: float = 1.0
## Сколько секунд после схода с края ещё можно прыгнуть.
@export var coyote_time: float = 0.1
## Сколько секунд помнится нажатие прыжка до приземления.
@export var jump_buffer_time: float = 0.12

@export_group("Ступеньки")
## Самая высокая ступенька/бордюр, на которые боец заходит без прыжка, м.
@export var max_step_height: float = 0.35
## Насколько за краем ступеньки меряем её высоту. Меньше глубины ступеньки.
@export var step_probe_distance: float = 0.06
## Как быстро камера догоняет тело после шага на ступеньку.
@export var step_camera_smoothing: float = 14.0

@export_group("Присед")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.15
@export var stand_eye_height: float = 1.62
@export var crouch_eye_height: float = 1.0
## Скорость опускания/подъёма камеры при приседе.
@export var eye_height_speed: float = 12.0
## false — сидим, пока клавиша зажата; true — нажатие переключает.
@export var crouch_toggle: bool = false

@export_group("Сеть")
## Насколько «в прошлом» показываем чужих бойцов. Больше — плавнее при
## потерях пакетов, меньше — меньше отставание картинки.
@export var interpolation_delay: float = 0.1
## Если снимки перестали приходить, сколько секунд продолжаем движение по инерции.
@export var max_extrapolation: float = 0.2

@export_group("Столкновения с бойцами")
## Ближе этого (по горизонтали) бойцы мягко расталкиваются.
@export var separation_distance: float = 0.7
## Скорость расталкивания при полном наложении, м/с.
@export var separation_speed: float = 4.0

@export_group("Камера")
## Угол обзора и чувствительность мыши — в GameSettings (меню паузы).
@export var sprint_fov_bonus: float = 6.0
@export var head_bob_enabled: bool = true
## Длина шага, м: один кач камеры вверх-вниз на шаг.
@export var bob_step_length: float = 1.6
@export var bob_amplitude: float = 0.03

## Ввод за один тик физики. На шаге с сетью именно эту структуру
## будем передавать/получать вместо прямого чтения клавиатуры.
class InputState:
	## x — вправо, y — назад (как у Input.get_vector: вперёд = -1).
	var move: Vector2 = Vector2.ZERO
	var jump_pressed: bool = false
	var sprint_held: bool = false
	var wants_crouch: bool = false
	var fire_held: bool = false
	var fire_pressed: bool = false
	var aim_held: bool = false
	var reload_pressed: bool = false
	## Смена оружия: −1 — нет, 0 — основное, 1 — пистолет, SWITCH_NEXT — следующее.
	var switch_to: int = -1

## Где был боец в момент времени (для проверки попаданий на хосте).
class HitPose:
	var time: float = 0.0
	var position: Vector3 = Vector3.ZERO
	var crouched: bool = false

## Снимок состояния чужого бойца.
class Snapshot:
	var time: float = 0.0
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pitch: float = 0.0
	var stance: int = 0
	var sprinting: bool = false
	var teleport_id: int = 0

var stance: Stance = Stance.STAND
var is_sprinting: bool = false
## Имя игрока (приходит при спавне).
var display_name: String = ""
## peer id игрока-владельца.
var peer_id: int = 0
## Для автотестов: если задан, используется вместо клавиатуры и мыши.
var debug_input: InputState = null

# Поля, которые рассылает хост через HostSync (см. player.tscn).
var health: float = MAX_HEALTH
var alive: bool = true:
	set(value):
		if alive == value:
			return
		alive = value
		_on_alive_changed()
var kills: int = 0
var deaths: int = 0
## Номер команды (TdmRules.TEAM_*). Меняет только хост.
var team: int = 0:
	set(value):
		if team == value:
			return
		team = value
		if is_node_ready():
			_apply_team_visuals()

## Только у владельца: бойца «заморозили» (итоги раунда) — ввод не читается.
var frozen: bool = false

# Поля, которые рассылает MultiplayerSynchronizer (см. player.tscn).
# Пишет их только владелец, остальные только читают.
var net_position: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_stance: int = 0
var net_sprinting: bool = false
## Время симуляции владельца (номер тика физики / тиков в секунду).
## Не настенные часы: тики физики иногда выполняются пачкой за один кадр,
## и по настенным часам движение выглядело бы рывками.
var net_time: float = 0.0
## Растёт при каждом телепорте: у остальных — «перепрыгнуть», а не плыть.
var net_teleport_id: int = 0
## Ствол в руках — номер в WeaponCatalog (−1 — ещё не известен).
var net_weapon: int = -1

var _snapshots: Array[Snapshot] = []
## Разница «наши часы − часы владельца» (включая пинг), сглаженная.
var _clock_offset: float = 0.0
var _has_clock_offset: bool = false
var _last_snapshot_time: float = -1.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _crouch_toggled: bool = false
var _eye_height: float = 0.0
var _bob_phase: float = 0.0
## Плавное покачивание: 0..1, растёт/спадает, а не обрывается.
var _bob_strength: float = 0.0
## Смещение камеры вниз после шага на ступеньку (тянется к 0).
var _step_camera_offset: float = 0.0
## Плоский низ (цилиндр), а не капсула: края ступенек не превращаются
## в «горки», и высота шага считается точно.
var _body_shape: CylinderShape3D
## Отдача, которая ещё не «доехала» до камеры (рад: x — вверх, y — вбок).
var _pending_kick: Vector2 = Vector2.ZERO
## Только на хосте: история положений и ограничение скорострельности.
var _history: Array[HitPose] = []
var _server_shot_times: Array[float] = []
var _awaiting_respawn: bool = false
var _body_material: StandardMaterial3D
## Команда своего бойца, под которую сейчас настроена подпись (−1 — ещё не настроена).
var _label_for_team: int = -1
## Колесо мыши крутнули между тиками физики.
var _wheel_switch_pending: bool = false

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _camera: Camera3D = $Camera3D
## Отдельная камера для ствола и рук (только у своего бойца).
var _viewmodel_layer: ViewmodelLayer
@onready var _head: Node3D = $Head
@onready var _visor: MeshInstance3D = $Head/Visor
@onready var _name_label: Label3D = $NameLabel
@onready var _sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var weapon: WeaponController = $WeaponController


## Вызывается до добавления в дерево (на всех машинах одинаково).
func setup(peer_id: int, player_name: String, spawn_transform: Transform3D, team_id: int) -> void:
	name = str(peer_id)
	self.peer_id = peer_id
	display_name = player_name
	team = team_id
	transform = spawn_transform
	set_multiplayer_authority(peer_id)
	# Здоровье и счёт принадлежат хосту, а не владельцу бойца.
	get_node(^"HostSync").set_multiplayer_authority(1)


func _ready() -> void:
	# Форма из сцены общая для всех копий бойца — делаем свою,
	# иначе присед одного игрока «присаживал» бы всех.
	_body_shape = (_collision.shape as CylinderShape3D).duplicate() as CylinderShape3D
	_collision.shape = _body_shape
	_apply_stance_shape(stand_height)

	_yaw = rotation.y
	_eye_height = stand_eye_height

	# Камера живёт отдельно от тела (top_level) и обновляется каждый кадр
	# отрисовки — так обзор мышью не отстаёт на тик физики.
	_camera.top_level = true
	_camera.fov = GameSettings.get_fov()

	_head.position.y = stand_eye_height
	_name_label.text = display_name

	add_to_group(PLAYERS_GROUP)
	var is_local: bool = is_multiplayer_authority()
	weapon.setup(self, _camera, _head, is_local)
	_camera.current = is_local
	if is_local:
		_viewmodel_layer = ViewmodelLayer.new(_camera)
		add_child(_viewmodel_layer)
		add_to_group(LOCAL_PLAYER_GROUP)
		# Своё тело не видим, но тень от него остаётся.
		_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_name_label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_write_net_state()
	else:
		_sync.synchronized.connect(_on_net_state_received)
	_body_material = (_body_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_body_mesh.material_override = _body_material
	_apply_team_visuals()
	_apply_alive_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# screen_relative не зависит от разрешения окна и растяжения.
		# В прицеле чувствительность ниже — пропорционально приближению.
		var zoom: float = _camera.fov / GameSettings.get_fov()
		var delta_rad: Vector2 = motion.screen_relative * deg_to_rad(GameSettings.get_sensitivity()) * zoom
		_yaw = wrapf(_yaw - delta_rad.x, -PI, PI)
		_pitch = clampf(_pitch - delta_rad.y, -PITCH_LIMIT, PITCH_LIMIT)
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP
				or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_wheel_switch_pending = true


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate(_read_input(), delta)
		_write_net_state()
	else:
		_apply_remote_state()
	if multiplayer.is_server():
		_record_history()


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_apply_pending_kick(delta)
		_update_camera(delta)
	else:
		_update_remote_head(delta)
		_update_name_label()


## Телепорт (спавн/респавн) без «размазывания» интерполяцией.
func teleport(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	_yaw = rotation.y
	_pitch = 0.0
	_pending_kick = Vector2.ZERO
	net_teleport_id += 1
	reset_physics_interpolation()
	_write_net_state()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Направление взгляда (−Z — вперёд).
func get_view_basis() -> Basis:
	return Basis.from_euler(Vector3(_pitch, _yaw, 0.0))


func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * _eye_height


## Повернуть взгляд (для тестов и спавна). Углы в радианах.
func set_look(yaw: float, pitch: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_pending_kick = Vector2.ZERO


func get_pitch() -> float:
	return _pitch


## Толчок камеры от отдачи (радианы). Доезжает до камеры за пару кадров.
func add_view_kick(pitch_up: float, yaw_side: float) -> void:
	_pending_kick += Vector2(pitch_up, yaw_side)


func _apply_pending_kick(delta: float) -> void:
	if _pending_kick == Vector2.ZERO:
		return
	var step: Vector2 = _pending_kick * (1.0 - exp(-35.0 * delta))
	if _pending_kick.length() < 0.0002:
		step = _pending_kick
	_pending_kick -= step
	_pitch = clampf(_pitch + step.x, -PITCH_LIMIT, PITCH_LIMIT)
	_yaw = wrapf(_yaw - step.y, -PI, PI)


# --- Ввод -----------------------------------------------------------------

func _read_input() -> InputState:
	if debug_input != null:
		var forced: InputState = debug_input
		if not alive or frozen:
			return InputState.new()
		return forced
	var input := InputState.new()
	if not alive or frozen:
		return input
	# Курсор свободен (меню паузы, окно не в фокусе) — боец стоит.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		input.wants_crouch = stance == Stance.CROUCH
		return input
	input.move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	input.jump_pressed = Input.is_action_just_pressed(&"jump")
	input.sprint_held = Input.is_action_pressed(&"sprint")
	input.fire_held = Input.is_action_pressed(&"fire")
	input.fire_pressed = Input.is_action_just_pressed(&"fire")
	input.aim_held = Input.is_action_pressed(&"aim")
	input.reload_pressed = Input.is_action_just_pressed(&"reload")
	if Input.is_action_just_pressed(&"weapon_primary"):
		input.switch_to = 0
	elif Input.is_action_just_pressed(&"weapon_secondary"):
		input.switch_to = 1
	elif _wheel_switch_pending:
		input.switch_to = SWITCH_NEXT
	_wheel_switch_pending = false

	if crouch_toggle:
		if Input.is_action_just_pressed(&"crouch"):
			_crouch_toggled = not _crouch_toggled
		input.wants_crouch = _crouch_toggled
	else:
		input.wants_crouch = Input.is_action_pressed(&"crouch")
	return input


# --- Симуляция ------------------------------------------------------------

func _simulate(input: InputState, delta: float) -> void:
	rotation.y = _yaw

	_update_timers(input, delta)
	_update_stance(input)
	_update_sprint(input)

	if not is_on_floor():
		velocity += get_gravity() * delta

	_try_jump()
	_apply_horizontal_movement(input, delta)

	# Мягкое расталкивание: добавка к скорости только на этот тик.
	var push: Vector3 = _get_separation_velocity() if alive else Vector3.ZERO
	velocity += push
	var y_before: float = global_position.y
	var was_on_floor: bool = is_on_floor()
	if was_on_floor:
		_try_step_up(delta)
	move_and_slide()
	# Шаг на ступеньку вверх или вниз — тело переставляется сразу, а камера
	# догоняет плавно (на пандусах изменения мелкие и сюда не попадают).
	var dy: float = global_position.y - y_before
	if was_on_floor and is_on_floor() and absf(dy) > 0.06:
		_step_camera_offset = clampf(_step_camera_offset - dy, -max_step_height, max_step_height)
	velocity.x -= push.x
	velocity.z -= push.z

	weapon.tick(input, delta)


func _update_timers(input: InputState, delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if input.jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _update_stance(input: InputState) -> void:
	var wants_crouch: bool = input.wants_crouch
	# Рывок из приседа встаёт (как в Battlefield).
	if stance == Stance.CROUCH and input.sprint_held and _is_moving_forward(input):
		wants_crouch = false
		_crouch_toggled = false

	if wants_crouch and stance == Stance.STAND:
		_set_stance(Stance.CROUCH)
	elif not wants_crouch and stance == Stance.CROUCH and _can_stand_up():
		_set_stance(Stance.STAND)


func _update_sprint(input: InputState) -> void:
	var can_sprint: bool = (
		input.sprint_held
		and stance == Stance.STAND
		and _is_moving_forward(input)
		and not weapon.blocks_sprint()
		and not input.fire_held
	)
	# В воздухе бег не начинается, но и не прерывается.
	if is_on_floor() or not can_sprint:
		is_sprinting = can_sprint


func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0 or _coyote_timer <= 0.0:
		return
	_jump_buffer_timer = 0.0

	# Прыжок из приседа сначала поднимает бойца.
	if stance == Stance.CROUCH:
		_crouch_toggled = false
		if _can_stand_up():
			_set_stance(Stance.STAND)
		return

	_coyote_timer = 0.0
	var gravity: float = get_gravity().length()
	velocity.y = sqrt(2.0 * gravity * jump_height)


func _apply_horizontal_movement(input: InputState, delta: float) -> void:
	var wish_dir := Vector3(input.move.x, 0.0, input.move.y).rotated(Vector3.UP, _yaw)
	var target: Vector3 = wish_dir * _get_target_speed()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if is_on_floor():
		var accel: float = ground_accel if wish_dir != Vector3.ZERO else ground_decel
		horizontal = horizontal.move_toward(target, accel * delta)
	elif wish_dir != Vector3.ZERO:
		# В воздухе без клавиш скорость сохраняется (инерция прыжка).
		horizontal = horizontal.move_toward(target, air_accel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Подъём на ступеньку: если впереди невысокое препятствие, а над ним есть
## пол — поднимаем бойца на его высоту, дальше move_and_slide идёт уже по нему.
## Пандусы сюда не попадают — по ним move_and_slide едет сам.
func _try_step_up(delta: float) -> bool:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return false
	var dir: Vector3 = horizontal.normalized()
	var start: Transform3D = global_transform
	var hit := KinematicCollision3D.new()

	# 1. Впереди что-то мешает? И это именно стенка, а не пандус.
	var motion: Vector3 = dir * maxf(horizontal.length() * delta, 0.05)
	if not test_move(start, motion, hit):
		return false
	if hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return false

	# 2. Высота ступеньки — лучом сверху вниз сразу за точкой касания.
	#    (Капсула внизу круглая, по ней высота края получается неточной.)
	var into: Vector3 = -Vector3(hit.get_normal().x, 0.0, hit.get_normal().z).normalized()
	var probe_xz: Vector3 = hit.get_position() + into * step_probe_distance
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(probe_xz.x, start.origin.y + max_step_height + 0.05, probe_xz.z),
		Vector3(probe_xz.x, start.origin.y - 0.01, probe_xz.z),
		collision_mask, [get_rid()])
	var ray_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if ray_hit.is_empty():
		return false
	var rise: float = (ray_hit["position"] as Vector3).y - start.origin.y
	if rise < 0.002 or rise > max_step_height:
		return false  # это уже стена
	if (ray_hit["normal"] as Vector3).angle_to(Vector3.UP) > floor_max_angle:
		return false

	# 3. Над ступенькой должно хватать места: поднимаемся и пробуем шагнуть.
	var lifted: Transform3D = start
	lifted.origin.y += rise + 0.003
	if test_move(start, lifted.origin - start.origin):
		return false  # упёрлись головой
	if test_move(lifted, dir * 0.1, hit) and hit.get_travel().length() < 0.02:
		return false  # над «ступенькой» стена (подоконник и т.п.)

	# Поднимаем тело, горизонтальный шаг сделает move_and_slide, пол прижмёт floor_snap.
	global_position = lifted.origin
	return true


func _get_target_speed() -> float:
	var aim_mult: float = lerpf(1.0, weapon.weapon.ads_move_multiplier, weapon.aim_amount)
	if stance == Stance.CROUCH:
		return crouch_speed * aim_mult
	if is_sprinting:
		return sprint_speed
	return walk_speed * aim_mult


## Бойцы не проходят друг сквозь друга, но и не стоят «стеной»: если
## капсулы наложились, свой боец плавно отъезжает. Жёстких столкновений
## нет специально — чужой боец показан с задержкой 0.1 с, и об него
## застревали бы и дёргались, а товарищ мог бы перекрыть дверь.
func _get_separation_velocity() -> Vector3:
	var push := Vector3.ZERO
	for node: Node in get_tree().get_nodes_in_group(PLAYERS_GROUP):
		var other := node as Player
		if other == null or other == self or not other.alive:
			continue
		var offset: Vector3 = global_position - other.global_position
		if absf(offset.y) > stand_height * 0.8:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance >= separation_distance:
			continue
		var direction: Vector3
		if distance > 0.01:
			direction = offset / distance
		else:
			# Стоим точно друг в друге — расходимся в стороны по номеру игрока.
			var angle: float = float(peer_id) * 2.39996
			direction = Vector3(cos(angle), 0.0, sin(angle))
		push += direction * (1.0 - distance / separation_distance) * separation_speed
	return push


func _is_moving_forward(input: InputState) -> bool:
	return input.move.y < -0.5


# --- Присед ---------------------------------------------------------------

func _set_stance(new_stance: Stance) -> void:
	stance = new_stance
	_apply_stance_shape(crouch_height if stance == Stance.CROUCH else stand_height)


## Меняем высоту капсулы так, чтобы ноги оставались на месте.
func _apply_stance_shape(height: float) -> void:
	_body_shape.height = height
	_collision.position.y = height * 0.5
	if not alive:
		return  # модель лежит (см. _apply_alive_visuals)
	# Greybox-модель просто сжимаем по высоте.
	_body_mesh.scale.y = height / stand_height
	_body_mesh.position.y = height * 0.5


## Есть ли место над головой, чтобы встать.
func _can_stand_up() -> bool:
	var rise: float = stand_height - _body_shape.height
	return not test_move(global_transform, Vector3.UP * rise)


# --- Камера ---------------------------------------------------------------

func _update_camera(delta: float) -> void:
	var target_eye: float = crouch_eye_height if stance == Stance.CROUCH else stand_eye_height
	if not alive:
		target_eye = 0.35  # камера «падает» вместе с бойцом
	var eye_speed: float = eye_height_speed if alive else 4.0
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-eye_speed * delta))

	var bob_offset := Vector3.ZERO
	var speed: float = get_horizontal_speed()
	var walking: bool = head_bob_enabled and is_on_floor() and speed > 0.5
	# Сила покачивания меняется плавно: на ступеньках и кочках is_on_floor
	# может мигать — камера от этого не должна дёргаться.
	var target_strength: float = clampf(speed / sprint_speed, 0.0, 1.0) if walking else 0.0
	_bob_strength = lerpf(_bob_strength, target_strength, 1.0 - exp(-8.0 * delta))
	if _bob_strength > 0.001:
		# Фаза: полный круг = два шага (левой-правой). Вверх-вниз — раз на шаг.
		_bob_phase = fmod(_bob_phase + speed / (bob_step_length * 2.0) * delta * TAU, TAU)
		bob_offset.y = sin(_bob_phase * 2.0) * bob_amplitude * _bob_strength
		bob_offset.x = cos(_bob_phase) * bob_amplitude * 0.5 * _bob_strength
	else:
		_bob_phase = 0.0
	_step_camera_offset = lerpf(_step_camera_offset, 0.0, 1.0 - exp(-step_camera_smoothing * delta))
	bob_offset.y += _step_camera_offset

	var roll: float = 0.0 if alive else 0.5
	var view_basis := Basis.from_euler(Vector3(_pitch, _yaw, roll))
	# Позиция берётся из интерполированного тела — плавно на любом FPS,
	# а поворот — напрямую из мыши, без задержки.
	var body_origin: Vector3 = get_global_transform_interpolated().origin
	var eye_pos: Vector3 = body_origin + Vector3.UP * (_eye_height + bob_offset.y)
	eye_pos += view_basis.x * bob_offset.x
	_camera.global_transform = Transform3D(view_basis, eye_pos)

	var base_fov: float = GameSettings.get_fov()
	var hip_fov: float = base_fov + (sprint_fov_bonus if is_sprinting else 0.0)
	var aim: float = weapon.aim_amount
	# ads_fov в данных ствола задан для обзора 80° — приближение одинаковое при любой настройке.
	var ads_fov: float = weapon.weapon.ads_fov * base_fov / WeaponData.ADS_FOV_REFERENCE
	var target_fov: float = lerpf(hip_fov, ads_fov, aim * aim * (3.0 - 2.0 * aim))
	# Прицел управляет FOV напрямую, бег — плавно.
	if aim > 0.0:
		_camera.fov = target_fov
	else:
		_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-8.0 * delta))
	if _viewmodel_layer != null:
		_viewmodel_layer.sync(aim)


# --- Сеть: владелец -------------------------------------------------------

## Время симуляции этой машины (номер тика физики / тиков в секунду).
static func sim_time() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func _write_net_state() -> void:
	net_position = global_position
	net_yaw = _yaw
	net_pitch = _pitch
	net_stance = stance
	net_sprinting = is_sprinting
	net_time = sim_time()


# --- Сеть: чужой боец -----------------------------------------------------

func _on_net_state_received() -> void:
	if net_time <= _last_snapshot_time:
		return  # старый или повторный пакет
	_last_snapshot_time = net_time

	var now: float = sim_time()
	var sample: float = now - net_time
	if not _has_clock_offset or sample < _clock_offset:
		# Пакет пришёл быстрее обычного — это ближе к настоящей разнице часов.
		_clock_offset = sample
		_has_clock_offset = true
	else:
		# Медленно подстраиваемся, если пинг вырос.
		_clock_offset += (sample - _clock_offset) * 0.02

	var snap := Snapshot.new()
	snap.time = net_time
	snap.position = net_position
	snap.yaw = net_yaw
	snap.pitch = net_pitch
	snap.stance = net_stance
	snap.sprinting = net_sprinting
	snap.teleport_id = net_teleport_id
	_snapshots.append(snap)
	if _snapshots.size() > 40:
		_snapshots.pop_front()


func _apply_remote_state() -> void:
	if _snapshots.is_empty():
		return
	var now: float = sim_time()
	var render_time: float = now - _clock_offset - interpolation_delay

	# Выкидываем снимки, которые уже целиком в прошлом (оставляем один «до»).
	while _snapshots.size() >= 2 and _snapshots[1].time <= render_time:
		_snapshots.pop_front()

	var from: Snapshot = _snapshots[0]
	var target_position: Vector3 = from.position
	var target_yaw: float = from.yaw
	var target_pitch: float = from.pitch
	var shown: Snapshot = from

	if _snapshots.size() >= 2 and render_time > from.time:
		var to: Snapshot = _snapshots[1]
		if to.teleport_id != from.teleport_id:
			# Респавн/телепорт — без «полёта» через карту.
			_snapshots.pop_front()
			shown = to
			target_position = to.position
			target_yaw = to.yaw
			target_pitch = to.pitch
			global_position = target_position
			rotation.y = target_yaw
			reset_physics_interpolation()
		else:
			var span: float = maxf(to.time - from.time, 0.0001)
			var t: float = clampf((render_time - from.time) / span, 0.0, 1.0)
			target_position = from.position.lerp(to.position, t)
			target_yaw = lerp_angle(from.yaw, to.yaw, t)
			target_pitch = lerpf(from.pitch, to.pitch, t)
			shown = to if t > 0.5 else from
	elif _snapshots.size() >= 2:
		pass  # ещё не дошли до первого снимка — стоим на нём
	elif render_time > from.time and _snapshots.size() == 1:
		# Снимки кончились: чуть-чуть продолжаем по инерции.
		var extra: float = minf(render_time - from.time, max_extrapolation)
		target_position = from.position + velocity * extra

	if _snapshots.size() >= 2:
		var a: Snapshot = _snapshots[0]
		var b: Snapshot = _snapshots[1]
		var dt: float = maxf(b.time - a.time, 0.0001)
		velocity = (b.position - a.position) / dt
	elif render_time - from.time > max_extrapolation:
		velocity = Vector3.ZERO

	global_position = target_position
	rotation.y = target_yaw
	_yaw = target_yaw
	_pitch = target_pitch
	is_sprinting = shown.sprinting
	if shown.stance != stance:
		_set_stance(shown.stance as Stance)


## Голова чужого бойца: высота по позе и наклон по взгляду.
func _update_remote_head(delta: float) -> void:
	var target_eye: float = crouch_eye_height if stance == Stance.CROUCH else stand_eye_height
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-eye_height_speed * delta))
	_head.position.y = _eye_height
	_head.rotation.x = _pitch
	_name_label.position.y = _eye_height + 0.45


# --- Бой: стрельба --------------------------------------------------------

## Владелец выстрелил (вызывает WeaponController). У дробовика направлений
## несколько (по одному на дробинку), но сообщение хосту одно.
func fire_shot(origin: Vector3, directions: PackedVector3Array, weapon_index: int) -> void:
	var data: WeaponData = WeaponCatalog.get_by_index(weapon_index)
	var bullets: BulletManager = _get_bullets()
	var is_host: bool = multiplayer.is_server()
	if bullets != null:
		for direction: Vector3 in directions:
			bullets.spawn(origin, direction, data, peer_id, team, is_host, 0.0, true)
	if is_host:
		_client_shot_fx.rpc(origin, directions, weapon_index)
	else:
		_server_fire.rpc_id(1, origin, directions, weapon_index)


## Клиент → хост: «я выстрелил отсюда туда из такого ствола».
@rpc("any_peer", "call_remote", "reliable", 1)
func _server_fire(origin: Vector3, directions: PackedVector3Array, weapon_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != peer_id or not alive:
		return
	var data: WeaponData = WeaponCatalog.get_by_index(weapon_index)
	# Простые проверки от явной ерунды (игра для друзей, без античита).
	if data == null or directions.is_empty() or directions.size() > maxi(data.pellets, 1):
		return
	if origin.distance_to(global_position + Vector3.UP * 1.2) > 4.0:
		return
	if not _server_rate_ok(data):
		return
	var rewind: float = clampf(float(Network.get_peer_rtt_ms(sender)) / 1000.0, 0.0, MAX_REWIND)
	var bullets: BulletManager = _get_bullets()
	if bullets != null:
		for direction: Vector3 in directions:
			bullets.spawn(origin, direction.normalized(), data, peer_id, team, true, rewind, false)
	weapon.play_remote_shot(weapon_index)
	_client_shot_fx.rpc(origin, directions, weapon_index)


## Хост → все: «боец выстрелил» (трассер, вспышка, звук).
@rpc("any_peer", "call_remote", "unreliable", 1)
func _client_shot_fx(origin: Vector3, directions: PackedVector3Array, weapon_index: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_multiplayer_authority():
		return
	var data: WeaponData = WeaponCatalog.get_by_index(weapon_index)
	if data == null:
		return
	var bullets: BulletManager = _get_bullets()
	if bullets != null:
		for direction: Vector3 in directions:
			bullets.spawn(origin, direction.normalized(), data, peer_id, team, false, 0.0, false)
	weapon.play_remote_shot(weapon_index)


func _server_rate_ok(data: WeaponData) -> bool:
	var now: float = sim_time()
	while not _server_shot_times.is_empty() and _server_shot_times[0] < now - 1.0:
		_server_shot_times.pop_front()
	# Пакеты приходят пачками, поэтому запас в полтора раза + 3 выстрела.
	# Берём самый скорострельный ствол каталога: игрок мог только что сменить оружие.
	var allowed: int = int(maxf(data.fire_rate_rpm, 950.0) / 60.0 * 1.5) + 3
	if _server_shot_times.size() >= allowed:
		return false
	_server_shot_times.append(now)
	return true


func _get_bullets() -> BulletManager:
	return get_tree().get_first_node_in_group(BulletManager.GROUP) as BulletManager


# --- Бой: история положений (хост) ----------------------------------------

func _record_history() -> void:
	var pose := HitPose.new()
	pose.time = sim_time()
	pose.position = global_position
	pose.crouched = stance == Stance.CROUCH
	_history.append(pose)
	while _history.size() > 2 and _history[0].time < pose.time - HISTORY_SECONDS:
		_history.pop_front()


## Где был боец в момент time (по часам хоста), с интерполяцией.
func get_hit_pose(time: float) -> HitPose:
	if _history.is_empty():
		var now_pose := HitPose.new()
		now_pose.time = sim_time()
		now_pose.position = global_position
		now_pose.crouched = stance == Stance.CROUCH
		return now_pose
	if time <= _history[0].time:
		return _history[0]
	for i: int in range(_history.size() - 1, 0, -1):
		var a: HitPose = _history[i - 1]
		var b: HitPose = _history[i]
		if a.time <= time:
			if time >= b.time:
				return b
			var t: float = (time - a.time) / maxf(b.time - a.time, 0.0001)
			var pose := HitPose.new()
			pose.time = time
			# Телепорт (респавн) — не тянем хитбокс через карту.
			if a.position.distance_to(b.position) > 3.0:
				pose.position = b.position
			else:
				pose.position = a.position.lerp(b.position, t)
			pose.crouched = b.crouched if t > 0.5 else a.crouched
			return pose
	return _history[_history.size() - 1]


# --- Бой: урон, смерть, респавн -------------------------------------------

## Только на хосте.
func server_apply_damage(amount: float, attacker_id: int, headshot: bool, from_position: Vector3) -> void:
	if not multiplayer.is_server() or not alive:
		return
	health = maxf(health - amount, 0.0)
	var killed: bool = health <= 0.0
	_client_damaged.rpc_id(peer_id, from_position, amount)
	if Network.players.has(attacker_id) or attacker_id == 1:
		_client_hit_confirmed.rpc_id(attacker_id, headshot, killed)
	if killed:
		alive = false
		deaths += 1
		_awaiting_respawn = true
		killed_on_host.emit(self, attacker_id, headshot)


## Только на хосте: вернуть бойца в бой на точке спавна.
func server_respawn(spawn_transform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	_awaiting_respawn = true
	_client_respawn.rpc_id(peer_id, spawn_transform)


@rpc("any_peer", "call_local", "reliable")
func _client_damaged(from_position: Vector3, amount: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	damaged.emit(from_position, amount)


@rpc("any_peer", "call_local", "reliable")
func _client_hit_confirmed(headshot: bool, killed: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	# Сигнал шлёт боец-жертва, а слушает HUD стрелка — через своего бойца.
	var shooter := get_tree().get_first_node_in_group(LOCAL_PLAYER_GROUP) as Player
	if shooter != null:
		shooter.hit_confirmed.emit(headshot, killed)


## Хост → владелец: «возродись здесь».
@rpc("any_peer", "call_local", "reliable")
func _client_respawn(spawn_transform: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	if stance == Stance.CROUCH:
		_set_stance(Stance.STAND)
	teleport(spawn_transform)
	health = MAX_HEALTH
	alive = true
	# Снаряжение из меню применяется при каждом появлении.
	weapon.equip_loadout()
	_server_respawn_done.rpc_id(1)


## Владелец → хост: «я уже на точке спавна» — теперь можно оживлять для всех.
@rpc("any_peer", "call_local", "reliable")
func _server_respawn_done() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if not _awaiting_respawn:
		return
	_awaiting_respawn = false
	_history.clear()
	health = MAX_HEALTH
	alive = true


func _on_alive_changed() -> void:
	if not is_node_ready():
		return
	_apply_alive_visuals()
	if not alive and is_multiplayer_authority():
		weapon.cancel_reload()
	alive_changed.emit(alive)


## Мёртвый боец лежит; оружие и имя скрыты.
func _apply_alive_visuals() -> void:
	weapon.set_world_gun_visible(alive)
	_visor.visible = alive
	if alive:
		_body_mesh.rotation = Vector3.ZERO
		_apply_stance_shape(_body_shape.height)
		_label_for_team = -1  # подпись снова покажет _update_name_label
	else:
		_body_mesh.scale = Vector3.ONE
		_body_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_body_mesh.position = Vector3(0.0, 0.36, 0.0)
		_name_label.visible = false


# --- Команда --------------------------------------------------------------

func _apply_team_visuals() -> void:
	if _body_material != null:
		_body_material.albedo_color = TEAM_BODY_COLORS[clampi(team, 0, TEAM_BODY_COLORS.size() - 1)]
	_label_for_team = -1


## Подпись над чужим бойцом: у своих — имя цветом команды, видно сквозь стены;
## у врагов подписи нет (иначе находили бы их по именам).
func _update_name_label() -> void:
	var local_team: int = _get_local_team()
	if local_team == _label_for_team:
		return
	_label_for_team = local_team
	var friendly: bool = team != 0 and team == local_team
	_name_label.visible = friendly and alive
	_name_label.no_depth_test = friendly
	_name_label.modulate = TdmRules.TEAM_COLORS[clampi(team, 0, 2)]


func _get_local_team() -> int:
	var rules: TdmRules = TdmRules.get_rules(get_tree())
	return rules.get_local_team() if rules != null else 0
