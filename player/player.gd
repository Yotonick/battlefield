class_name Player
extends CharacterBody3D
## Боец от первого лица: ходьба, бег, присед, прыжок, обзор мышью.
##
## Шаг v0.1-1 — только локальная игра. Код заранее разделён на
## «чтение ввода» (_read_input) и «симуляцию» (_simulate), чтобы на шаге
## с сетью ввод можно было получать не с клавиатуры, а от владельца бойца.

enum Stance { STAND, CROUCH }

## Предел наклона камеры вверх/вниз.
const PITCH_LIMIT: float = 1.5533430  # 89°
## Группа, по которой UI находит своего (локального) бойца.
const LOCAL_PLAYER_GROUP: StringName = &"local_player"

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

@export_group("Присед")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.15
@export var stand_eye_height: float = 1.62
@export var crouch_eye_height: float = 1.0
## Скорость опускания/подъёма камеры при приседе.
@export var eye_height_speed: float = 12.0
## false — сидим, пока клавиша зажата; true — нажатие переключает.
@export var crouch_toggle: bool = false

@export_group("Камера")
## Градусов поворота на один пиксель движения мыши.
@export var mouse_sensitivity: float = 0.12
@export var base_fov: float = 80.0
@export var sprint_fov_bonus: float = 6.0
@export var head_bob_enabled: bool = true
## Шагов покачивания на метр пройденного пути.
@export var bob_frequency: float = 0.9
@export var bob_amplitude: float = 0.035

## Ввод за один тик физики. На шаге с сетью именно эту структуру
## будем передавать/получать вместо прямого чтения клавиатуры.
class InputState:
	## x — вправо, y — назад (как у Input.get_vector: вперёд = -1).
	var move: Vector2 = Vector2.ZERO
	var jump_pressed: bool = false
	var sprint_held: bool = false
	var wants_crouch: bool = false

var stance: Stance = Stance.STAND
var is_sprinting: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _crouch_toggled: bool = false
var _eye_height: float = 0.0
var _bob_phase: float = 0.0
var _capsule: CapsuleShape3D

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# Форма из сцены общая для всех копий бойца — делаем свою,
	# иначе присед одного игрока «присаживал» бы всех.
	_capsule = (_collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	_collision.shape = _capsule
	_apply_stance_shape(stand_height)

	_yaw = rotation.y
	_eye_height = stand_eye_height

	# Камера живёт отдельно от тела (top_level) и обновляется каждый кадр
	# отрисовки — так обзор мышью не отстаёт на тик физики.
	_camera.top_level = true
	_camera.fov = base_fov

	var is_local: bool = is_multiplayer_authority()
	_camera.current = is_local
	if is_local:
		add_to_group(LOCAL_PLAYER_GROUP)
		# Своё тело не видим, но тень от него остаётся.
		_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# screen_relative не зависит от разрешения окна и растяжения.
		var delta_rad: Vector2 = motion.screen_relative * deg_to_rad(mouse_sensitivity)
		_yaw = wrapf(_yaw - delta_rad.x, -PI, PI)
		_pitch = clampf(_pitch - delta_rad.y, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_simulate(_read_input(), delta)


func _process(delta: float) -> void:
	_update_camera(delta)


## Телепорт (спавн/респавн) без «размазывания» интерполяцией.
func teleport(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	_yaw = rotation.y
	_pitch = 0.0
	reset_physics_interpolation()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# --- Ввод -----------------------------------------------------------------

func _read_input() -> InputState:
	var input := InputState.new()
	input.move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	input.jump_pressed = Input.is_action_just_pressed(&"jump")
	input.sprint_held = Input.is_action_pressed(&"sprint")

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
	move_and_slide()


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


func _get_target_speed() -> float:
	if stance == Stance.CROUCH:
		return crouch_speed
	if is_sprinting:
		return sprint_speed
	return walk_speed


func _is_moving_forward(input: InputState) -> bool:
	return input.move.y < -0.5


# --- Присед ---------------------------------------------------------------

func _set_stance(new_stance: Stance) -> void:
	stance = new_stance
	_apply_stance_shape(crouch_height if stance == Stance.CROUCH else stand_height)


## Меняем высоту капсулы так, чтобы ноги оставались на месте.
func _apply_stance_shape(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5
	# Greybox-модель просто сжимаем по высоте.
	_body_mesh.scale.y = height / stand_height
	_body_mesh.position.y = height * 0.5


## Есть ли место над головой, чтобы встать.
func _can_stand_up() -> bool:
	var rise: float = stand_height - _capsule.height
	return not test_move(global_transform, Vector3.UP * rise)


# --- Камера ---------------------------------------------------------------

func _update_camera(delta: float) -> void:
	var target_eye: float = crouch_eye_height if stance == Stance.CROUCH else stand_eye_height
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-eye_height_speed * delta))

	var bob_offset := Vector3.ZERO
	var speed: float = get_horizontal_speed()
	if head_bob_enabled and is_on_floor() and speed > 0.5:
		_bob_phase = fmod(_bob_phase + speed * bob_frequency * delta * TAU, TAU)
		var strength: float = clampf(speed / sprint_speed, 0.0, 1.0)
		bob_offset.y = sin(_bob_phase * 2.0) * bob_amplitude * strength
		bob_offset.x = cos(_bob_phase) * bob_amplitude * 0.5 * strength
	else:
		_bob_phase = 0.0

	var view_basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	# Позиция берётся из интерполированного тела — плавно на любом FPS,
	# а поворот — напрямую из мыши, без задержки.
	var body_origin: Vector3 = get_global_transform_interpolated().origin
	var eye_pos: Vector3 = body_origin + Vector3.UP * (_eye_height + bob_offset.y)
	eye_pos += view_basis.x * bob_offset.x
	_camera.global_transform = Transform3D(view_basis, eye_pos)

	var target_fov: float = base_fov + (sprint_fov_bonus if is_sprinting else 0.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-8.0 * delta))
