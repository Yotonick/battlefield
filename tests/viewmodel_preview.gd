extends SceneTree
## Быстрый предпросмотр стволов (и рук) от первого лица без матча и сети.
##   godot --path . --resolution 1280x720 --script res://tests/viewmodel_preview.gd -- --screens=/tmp/vm [--only=rifle_ak]
## Для каждого ствола сохраняет <id>_hip.png и <id>_ads.png.

var _screens: String = "/tmp/vm"
var _only: String = ""
## --side: вид сбоку (ортографический) с красной линией прицела y = 0.
var _side: bool = false
var _camera: Camera3D
var _world: Node3D
var _layer: ViewmodelLayer
var _gun: GunView
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


func _process(_delta: float) -> bool:
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
	if _step % 3 == 0:
		if _queue.is_empty():
			return true
		if _gun != null:
			_gun.queue_free()
		_gun = GunView.new(_queue[0])
		_gun.set_first_person()
		_camera.add_child(_gun)
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


func _save(shot_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [_screens, shot_name])
	if OS.get_cmdline_user_args().has("--alpha") and not _side:
		_layer.camera.get_viewport().get_texture().get_image().save_png("%s/%s_layer.png" % [_screens, shot_name])
