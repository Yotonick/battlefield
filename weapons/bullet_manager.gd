class_name BulletManager
extends Node3D
## Все летящие пули матча. Пуля — не узел, а запись в массиве: так дешевле.
## Каждый тик физики пуля пролетает отрезок (скорость × время, плюс гравитация),
## и отрезок проверяется лучом против мира и математически против бойцов.
##
## На хосте пули «настоящие» (authoritative): попадание наносит урон.
## У клиентов пули только для вида: трассер, след на стене.
## Пуля стрелка-клиента на хосте проверяется по бойцам «в прошлом» —
## на столько, на сколько стрелок видел их с опозданием (компенсация пинга).

const GROUP: StringName = &"bullet_manager"
## Слой мира в физике (пули не видят тела бойцов — по ним считает HitMath).
const WORLD_MASK: int = 1
const MAX_BULLETS: int = 256
const MAX_HOLES: int = 96
const TRACER_LENGTH: float = 3.0
## Свои трассеры начинаются не у глаз, а чуть дальше.
const OWN_TRACER_SKIP: float = 2.5
const KILL_Y: float = -60.0

## Пуля попала в мир (для эффектов и тестов).
signal world_impact(position: Vector3, normal: Vector3)
## Только на хосте: пуля попала в бойца.
signal soldier_hit(target: Player, shooter_id: int, damage: float, headshot: bool)

class Bullet:
	var position: Vector3
	var previous_position: Vector3
	var velocity: Vector3
	var origin: Vector3
	var weapon: WeaponData
	var shooter_id: int = 0
	## Команда стрелка: сквозь своих пуля пролетает (огня по своим нет).
	var shooter_team: int = 0
	var authoritative: bool = false
	## На сколько секунд назад смотреть бойцов (только на хосте).
	var rewind: float = 0.0
	var age: float = 0.0
	var travelled: float = 0.0
	var own: bool = false
	var alive: bool = true

var _bullets: Array[Bullet] = []
var _tracers: MultiMeshInstance3D
var _holes: Array[MeshInstance3D] = []
var _next_hole: int = 0
var _hit_flags: Array[bool] = [false]


func _ready() -> void:
	add_to_group(GROUP)
	_tracers = MultiMeshInstance3D.new()
	_tracers.name = "Tracers"
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.025, 0.025, 1.0)
	var tracer_material := StandardMaterial3D.new()
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color(1.0, 0.82, 0.45)
	tracer_mesh.material = tracer_material
	multimesh.mesh = tracer_mesh
	multimesh.instance_count = MAX_BULLETS
	multimesh.visible_instance_count = 0
	_tracers.multimesh = multimesh
	# Положение трассеров считаем сами каждый кадр — без интерполяции движка.
	_tracers.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_tracers)


## Выпустить пулю. own — пуля своего бойца (трассер начинается дальше от глаз).
func spawn(origin: Vector3, direction: Vector3, weapon: WeaponData, shooter_id: int,
		shooter_team: int, authoritative: bool, rewind: float, own: bool) -> void:
	if _bullets.size() >= MAX_BULLETS:
		_bullets.pop_front()
	var bullet := Bullet.new()
	bullet.position = origin
	bullet.previous_position = origin
	bullet.origin = origin
	bullet.velocity = direction.normalized() * weapon.muzzle_velocity
	bullet.weapon = weapon
	bullet.shooter_id = shooter_id
	bullet.shooter_team = shooter_team
	bullet.authoritative = authoritative
	bullet.rewind = rewind
	bullet.own = own
	_bullets.append(bullet)


func get_active_count() -> int:
	return _bullets.size()


func _physics_process(delta: float) -> void:
	if _bullets.is_empty():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var soldiers: Array[Node] = get_tree().get_nodes_in_group(Player.PLAYERS_GROUP)
	var now: float = Player.sim_time()
	for bullet: Bullet in _bullets:
		_step(bullet, delta, space, soldiers, now)
	_bullets = _bullets.filter(func(b: Bullet) -> bool: return b.alive)


func _step(bullet: Bullet, delta: float, space: PhysicsDirectSpaceState3D,
		soldiers: Array[Node], now: float) -> void:
	bullet.previous_position = bullet.position
	var gravity: Vector3 = Vector3.DOWN * 9.8 * bullet.weapon.gravity_scale
	var start: Vector3 = bullet.position
	var end: Vector3 = start + bullet.velocity * delta + gravity * (0.5 * delta * delta)
	bullet.velocity += gravity * delta
	bullet.age += delta

	var segment: Vector3 = end - start
	var length: float = segment.length()
	if length < 0.0001:
		bullet.alive = false
		return
	var dir: Vector3 = segment / length

	# 1. Мир.
	var world_dist: float = INF
	var world_hit: Dictionary = {}
	var query := PhysicsRayQueryParameters3D.create(start, end, WORLD_MASK)
	query.hit_back_faces = false
	world_hit = space.intersect_ray(query)
	if not world_hit.is_empty():
		world_dist = start.distance_to(world_hit[&"position"] as Vector3)

	# 2. Бойцы.
	var best_dist: float = world_dist
	var best_target: Player = null
	var best_headshot: bool = false
	for node: Node in soldiers:
		var soldier := node as Player
		if soldier == null or not soldier.alive or soldier.peer_id == bullet.shooter_id:
			continue
		if bullet.shooter_team != 0 and soldier.team == bullet.shooter_team:
			continue
		var feet: Vector3
		var crouched: bool
		if bullet.authoritative:
			var rewind: float = bullet.rewind
			# Своего бойца хост видит без задержки интерполяции, а стрелок —
			# с ней: смотрим ещё дальше в прошлое.
			if soldier.is_multiplayer_authority() and bullet.shooter_id != multiplayer.get_unique_id():
				rewind += soldier.interpolation_delay
			var pose: Player.HitPose = soldier.get_hit_pose(now - rewind)
			feet = pose.position
			crouched = pose.crouched
		else:
			feet = soldier.global_position
			crouched = soldier.stance == Player.Stance.CROUCH
		var dist: float = HitMath.ray_vs_soldier(start, dir, length, feet, crouched, _hit_flags)
		if dist >= 0.0 and dist < best_dist:
			best_dist = dist
			best_target = soldier
			best_headshot = _hit_flags[0]

	if best_target != null:
		bullet.position = start + dir * best_dist
		bullet.travelled += best_dist
		bullet.alive = false
		if bullet.authoritative:
			var distance: float = bullet.origin.distance_to(bullet.position)
			var damage: float = bullet.weapon.get_damage(distance, best_headshot)
			soldier_hit.emit(best_target, bullet.shooter_id, damage, best_headshot)
		return

	if not world_hit.is_empty():
		var hit_pos: Vector3 = world_hit[&"position"] as Vector3
		var normal: Vector3 = world_hit[&"normal"] as Vector3
		bullet.position = hit_pos
		bullet.travelled += world_dist
		bullet.alive = false
		_spawn_impact(hit_pos, normal)
		world_impact.emit(hit_pos, normal)
		return

	bullet.position = end
	bullet.travelled += length
	if bullet.age > bullet.weapon.bullet_lifetime or end.y < KILL_Y:
		bullet.alive = false


# --- Вид ------------------------------------------------------------------

func _process(_delta: float) -> void:
	var multimesh: MultiMesh = _tracers.multimesh
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var count: int = 0
	for bullet: Bullet in _bullets:
		var head: Vector3 = bullet.previous_position.lerp(bullet.position, fraction)
		var flown: float = bullet.origin.distance_to(head)
		var skip: float = OWN_TRACER_SKIP if bullet.own else 0.3
		var length: float = minf(TRACER_LENGTH, flown - skip)
		if length <= 0.05:
			continue
		var dir: Vector3 = bullet.velocity.normalized()
		var look := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		var basis := Basis(look.x, look.y, look.z * length)
		var center: Vector3 = head - dir * (length * 0.5)
		multimesh.set_instance_transform(count, Transform3D(basis, center))
		count += 1
	multimesh.visible_instance_count = count


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	_place_hole(pos, normal)
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.7, 0.62, 0.8)
	sphere.material = material
	puff.mesh = sphere
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	puff.global_position = pos + normal * 0.05
	var tween: Tween = puff.create_tween().set_parallel(true)
	tween.tween_property(puff, ^"scale", Vector3.ONE * 3.0, 0.35)
	tween.tween_property(material, ^"albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(puff.queue_free)


func _place_hole(pos: Vector3, normal: Vector3) -> void:
	var hole: MeshInstance3D
	if _holes.size() < MAX_HOLES:
		hole = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.06)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.08, 0.08, 0.07)
		material.roughness = 1.0
		quad.material = material
		hole.mesh = quad
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hole.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(hole)
		_holes.append(hole)
	else:
		hole = _holes[_next_hole]
		_next_hole = (_next_hole + 1) % MAX_HOLES
	var up: Vector3 = Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD
	# QuadMesh смотрит в +Z — разворачиваем лицом по нормали.
	var basis := Basis.looking_at(-normal, up)
	basis = basis.rotated(normal, randf() * TAU)
	hole.global_transform = Transform3D(basis, pos + normal * 0.004)
