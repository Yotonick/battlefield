class_name GreyboxGun
extends Node3D
## Временная модель автомата из блоков (в v0.2 — настоящая модель).
## Ствол смотрит в −Z. Линия прицела (мушка/целик) — на высоте y = 0,
## поэтому в прицеле модель ставится ровно по центру камеры.

const METAL := Color(0.16, 0.17, 0.17)
const WOOD := Color(0.36, 0.22, 0.12)

var muzzle: Marker3D
var _flash_mesh: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_timer: float = 0.0
var _stock: MeshInstance3D


func _init() -> void:
	name = "Gun"
	var metal := _material(METAL, 0.45)
	var wood := _material(WOOD, 0.8)
	# Ствольная коробка, ствол, цевьё, приклад, рукоять, магазин, прицел.
	_box(Vector3(0.05, 0.065, 0.36), Vector3(0, -0.055, -0.1), metal)
	_box(Vector3(0.022, 0.022, 0.32), Vector3(0, -0.04, -0.44), metal)
	_box(Vector3(0.048, 0.05, 0.2), Vector3(0, -0.05, -0.33), wood)
	_stock = _box(Vector3(0.042, 0.075, 0.26), Vector3(0, -0.075, 0.2), wood)
	_box(Vector3(0.035, 0.09, 0.04), Vector3(0, -0.12, 0.02), wood, Vector3(-0.35, 0, 0))
	_box(Vector3(0.035, 0.15, 0.06), Vector3(0, -0.15, -0.14), metal, Vector3(0.3, 0, 0))
	_box(Vector3(0.006, 0.04, 0.006), Vector3(0, -0.02, -0.56), metal)
	_box(Vector3(0.008, 0.016, 0.01), Vector3(-0.012, -0.006, -0.06), metal)
	_box(Vector3(0.008, 0.016, 0.01), Vector3(0.012, -0.006, -0.06), metal)

	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, -0.04, -0.62)
	add_child(muzzle)

	_flash_mesh = MeshInstance3D.new()
	var flash_shape := SphereMesh.new()
	flash_shape.radius = 0.05
	flash_shape.height = 0.16
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.75, 0.35)
	flash_shape.material = flash_material
	_flash_mesh.mesh = flash_shape
	_flash_mesh.rotation.x = PI * 0.5
	_flash_mesh.position = Vector3(0, 0, -0.06)
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
	for child: Node in get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


## Модель от первого лица: без приклада (он упирался бы в камеру в прицеле)
## и без теней на мир, иначе тень «висит» у лица.
func set_first_person() -> void:
	_stock.visible = false
	for child: Node in get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(size: Vector3, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.rotation = rot
	add_child(instance)
	return instance


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
