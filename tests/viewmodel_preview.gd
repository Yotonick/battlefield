extends SceneTree
## Быстрый предпросмотр стволов (и рук) от первого лица без матча и сети.
##   godot --path . --resolution 1280x720 --script res://tests/viewmodel_preview.gd -- --screens=/tmp/vm [--only=rifle_ak]
## Для каждого ствола сохраняет <id>_hip.png и <id>_ads.png.

var _screens: String = "/tmp/vm"
var _only: String = ""
## --rig: руки со стволом снаружи (сбоку, сверху, спереди) — для настройки хвата.
var _rig: bool = false
var _rig_eye: Camera3D
## Куда смотрит камера в режиме --rig (координаты «глаза»: x вправо, −z вперёд) и с какого расстояния.
var _look := Vector3(0.12, -0.15, -0.45)
var _dist: float = 0.65
var _curl_override: float = -1.0
## --side: вид сбоку (ортографический) с красной линией прицела y = 0.
var _side: bool = false
var _camera: Camera3D
var _world: Node3D
var _layer: ViewmodelLayer
var _gun: GunView
var _arms: FirstPersonArms
var _queue: Array[WeaponData] = []
var _step: int = 0
var _frames: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screens="):
			_screens = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			_only = arg.get_slice("=", 1)
		elif arg == "--side":
			_side = true
		elif arg == "--rig":
			_rig = true
		elif arg.begins_with("--look="):
			var parts: PackedStringArray = arg.get_slice("=", 1).split(",")
			_look = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif arg.begins_with("--dist="):
			_dist = float(arg.get_slice("=", 1))
		elif arg.begins_with("--curl="):
			_curl_override = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_screens)

	var world := Node3D.new()
	_world = world
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.8, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.36, 0.4)
	plane.material = floor_material
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var post := MeshInstance3D.new()
	post.mesh = BoxMesh.new()
	post.scale = Vector3(1, 3, 1)
	post.position = Vector3(0, 1.5, -12)
	world.add_child(post)

	_camera = Camera3D.new()
	_camera.fov = GameSettings.FOV_DEFAULT
	_camera.position = Vector3(0, 1.65, 0)
	world.add_child(_camera)
	_camera.current = true
	_layer = ViewmodelLayer.new(_camera)
	root.add_child(_layer)
	var holder: Camera3D = _camera
	if _rig:
		# «Глаз» бойца — отдельная камера (не текущая); смотрим на неё со стороны.
		_rig_eye = Camera3D.new()
		_rig_eye.position = Vector3(0, 1.65, 0)
		world.add_child(_rig_eye)
		holder = _rig_eye
		_camera.cull_mask = 0xFFFFF
		_layer.visible = false
	if not OS.get_cmdline_user_args().has("--no-arms"):
		_arms = FirstPersonArms.new()
		holder.add_child(_arms)

	if _side:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 0.7
		_camera.position = Vector3(2.0, 1.65, -0.3)
		_camera.rotation_degrees = Vector3(0, 90, 0)
		_layer.queue_free()
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.002, 0.002, 3.0)
		var red := StandardMaterial3D.new()
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.albedo_color = Color.RED
		line_mesh.material = red
		line.mesh = line_mesh
		line.position = Vector3(0.1, 1.65, 0)
		world.add_child(line)
	for data: WeaponData in WeaponCatalog.WEAPONS:
		if _only == "" or String(data.id) == _only:
			_queue.append(data)


func _process(delta: float) -> bool:
	if _arms != null and _curl_override >= 0.0:
		_arms.ik.right.curl = _curl_override
		_arms.ik.left.curl = _curl_override
		_arms.ik.right.thumb_curl = _curl_override
		_arms.ik.left.thumb_curl = _curl_override
	if _arms != null and _gun != null and is_instance_valid(_gun) and not _gun.is_queued_for_deletion() and not _side:
		_arms.solve(_gun, delta)
	_frames += 1
	if _frames < 4:
		return false
	_frames = 0
	if _side:
		if _queue.is_empty():
			return true
		if _gun != null:
			_save("%s_side" % _queue.pop_front().id)
			_gun.free()
			_gun = null
			return false
		_gun = GunView.new(_queue[0])
		_world.add_child(_gun)
		_gun.position = Vector3(0, 1.65, 0)
		return false
	if _rig:
		return _rig_step()
	if _step % 3 == 0:
		if _queue.is_empty():
			return true
		if _gun != null:
			_gun.queue_free()
		_gun = GunView.new(_queue[0])
		_gun.set_first_person()
		(_rig_eye if _rig else _camera).add_child(_gun)
		_gun.position = _gun.weapon.view_hip
		_gun.rotation = _gun.weapon.view_hip_rot_deg * (PI / 180.0)
		_layer.sync(0.0)
	elif _step % 3 == 1:
		_save("%s_hip" % _gun.weapon.id)
		_gun.position = _gun.weapon.view_ads
		_gun.rotation = Vector3.ZERO
		_layer.sync(1.0)
	else:
		_save("%s_ads" % _gun.weapon.id)
		_queue.pop_front()
	_step += 1
	return false


## Направления взгляда камеры на руки: справа, сверху, спереди-слева, снизу-слева.
const RIG_VIEWS: Array[Vector3] = [Vector3(1, 0.05, 0), Vector3(0.05, 1, 0.1), Vector3(-0.5, 0.2, -1), Vector3(0.0, 0.35, 1.0)]
const RIG_NAMES: Array[String] = ["right", "top", "front", "below"]


func _rig_step() -> bool:
	var phase: int = _step % 6
	if phase == 0:
		if _queue.is_empty():
			return true
		if _gun != null:
			_gun.queue_free()
		_gun = GunView.new(_queue[0])
		_gun.set_first_person()
		_rig_eye.add_child(_gun)
		if OS.get_cmdline_user_args().has("--ads"):
			_gun.position = _gun.weapon.view_ads
		else:
			_gun.position = _gun.weapon.view_hip
			_gun.rotation = _gun.weapon.view_hip_rot_deg * (PI / 180.0)
	else:
		if phase > 1:
			_save("%s_rig_%s" % [_gun.weapon.id, RIG_NAMES[phase - 2]])
		if phase < 5:
			var target: Vector3 = _rig_eye.position + _look
			_camera.position = target + RIG_VIEWS[phase - 1].normalized() * _dist
			_camera.look_at(target, Vector3.UP if absf(RIG_VIEWS[phase - 1].normalized().y) < 0.9 else Vector3.FORWARD)
		else:
			_queue.pop_front()
	_step += 1
	return false


func _debug_hands() -> void:
	var k: Skeleton3D = _arms.skeleton
	var inv: Transform3D = _gun.global_transform.affine_inverse()
	for side: String in ["R", "L"]:
		var parts: PackedStringArray = []
		for bone_name: String in ["DEF-hand.", "DEF-f_middle.03.", "DEF-thumb.03.", "DEF-f_index.01.", "DEF-f_pinky.01."]:
			var bone: int = k.find_bone(bone_name + side)
			var p: Vector3 = inv * (k.global_transform * k.get_bone_global_pose(bone).origin)
			parts.append("%s(%.3f %.3f %.3f)" % [bone_name.trim_prefix("DEF-"), p.x, p.y, p.z])
		print("[hand %s] %s" % [side, " ".join(parts)])


func _save(shot_name: String) -> void:
	if _rig and shot_name.ends_with("right"):
		_arms.ik.modification_processed.connect(_debug_hands, CONNECT_ONE_SHOT)
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [_screens, shot_name])
	if OS.get_cmdline_user_args().has("--alpha") and not _side:
		_layer.camera.get_viewport().get_texture().get_image().save_png("%s/%s_layer.png" % [_screens, shot_name])
