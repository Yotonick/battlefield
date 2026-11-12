class_name GunView
extends Node3D
## Модель ствола из WeaponData (в руках от первого лица или «в мире» у чужих).
##
## Модель выравнивается сама: дуло в −Z, линия прицела на высоте y = 0
## (в прицеле модель стоит ровно по центру камеры), задний край — на
## rear_offset позади начала координат. Поэтому все стволы ставятся у камеры
## одинаково, а различия — в параметрах WeaponData.

var weapon: WeaponData
var muzzle: Marker3D
var _model: Node3D
var _flash_mesh: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_timer: float = 0.0


func _init(data: WeaponData) -> void:
	weapon = data
	name = "Gun"
	_model = data.model.instantiate() as Node3D
	add_child(_model)
	_fit_model()
	_build_flash()


## Масштаб, поворот и сдвиг модели под правила выше.
func _fit_model() -> void:
	_model.transform = Transform3D.IDENTITY
	# Сначала поворот вокруг вертикали (дуло в −Z), потом вокруг оси ствола.
	_model.basis = Basis(Vector3.FORWARD, deg_to_rad(weapon.model_roll_deg)) \
			* Basis(Vector3.UP, deg_to_rad(weapon.model_yaw_deg))
	var box: AABB = _get_model_aabb()
	var length: float = maxf(box.size.z, 0.001)
	var factor: float = weapon.model_length / length
	_model.scale = Vector3.ONE * factor
	box = _get_model_aabb()
	var top: float = box.position.y + box.size.y
	var rear: float = box.position.z + box.size.z
	_model.position = Vector3(
			-(box.position.x + box.size.x * 0.5),
			-(top - weapon.sight_drop),
			-(rear - weapon.rear_offset))

	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	# После сдвига верх модели — на высоте sight_drop, перед — на box.z + сдвиг.
	muzzle.position = Vector3(0.0, weapon.sight_drop - box.size.y * weapon.muzzle_drop,
			box.position.z + _model.position.z - 0.02)
	add_child(muzzle)


## Габариты модели в координатах этого узла (с учётом поворота и масштаба).
func _get_model_aabb() -> AABB:
	var result := AABB()
	var first: bool = true
	var to_local: Transform3D = Transform3D.IDENTITY
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var xform: Transform3D = _model.transform * _relative_transform(mesh_instance)
		var box: AABB = (to_local * xform) * mesh_instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Положение узла относительно корня модели (дерево ещё не в сцене,
## поэтому global_transform использовать нельзя).
func _relative_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != _model:
		var spatial := current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform


func _build_flash() -> void:
	_flash_mesh = MeshInstance3D.new()
	var flash_shape := SphereMesh.new()
	var size: float = 1.6 if weapon.category == WeaponData.Category.SHOTGUN else 1.0
	flash_shape.radius = 0.05 * size
	flash_shape.height = 0.16 * size
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.75, 0.35)
	flash_shape.material = flash_material
	_flash_mesh.mesh = flash_shape
	_flash_mesh.rotation.x = PI * 0.5
	_flash_mesh.position = Vector3(0, 0, -0.06 * size)
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	muzzle.add_child(_flash_mesh)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.4)
	_flash_light.light_energy = 2.0
	_flash_light.omni_range = 5.0
	_flash_light.visible = false
	muzzle.add_child(_flash_light)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_mesh.visible = false
			_flash_light.visible = false


func flash() -> void:
	_flash_timer = 0.05
	_flash_mesh.visible = true
	_flash_light.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	_flash_mesh.scale = Vector3.ONE * randf_range(0.8, 1.3)


## Видна только тень (своё оружие от третьего лица).
func set_shadow_only(enabled: bool) -> void:
	_set_shadows(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


## Модель от первого лица: без теней на мир (иначе тень «висит» у лица)
## и на отдельном визуальном слое — её рисует камера ViewmodelLayer.
func set_first_person() -> void:
	_set_shadows(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).layers = ViewmodelLayer.VISUAL_LAYER
	# Вспышка освещает и мир, и сам ствол — её видят обе камеры.
	_flash_light.layers |= ViewmodelLayer.VISUAL_LAYER


func _set_shadows(mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for node: Node in _model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = mode
