class_name FirstPersonArms
extends Node3D
## Руки от первого лица — руки самого манекена (решение 31).
##
## Из меша манекена оставляются только треугольники рук (по весам костей),
## тело и голова не рисуются. Узел висит на основной камере рядом со стволом
## (GunView) и рисуется камерой ViewmodelLayer. Кисти цепляются IK к точкам
## хвата ствола (WeaponData.grip_right / grip_left), плечи стоят в заданных
## точках у камеры — анатомия тела здесь не нужна, видно только предплечья и кисти.

const MANNEQUIN: PackedScene = preload("res://assets/characters/mannequin.glb")
## Кости, чьи вершины остаются в меше.
const ARM_BONE_PREFIXES: Array[String] = ["DEF-upper_arm.", "DEF-forearm.", "DEF-hand.",
		"DEF-f_", "DEF-thumb."]
## Плечи задаются в координатах ствола (WeaponData.shoulder_right/left):
## руки двигаются вместе со стволом, а плечи всегда ниже и позади поля
## зрения — в прицеле рука не закрывает экран.
## Куда смотрят локти (координаты камеры).
const POLE_RIGHT := Vector3(1.0, -0.7, 0.2)
const POLE_LEFT := Vector3(-0.8, -1.0, 0.1)
## Цвета: рукава (основной материал манекена) и перчатки/суставы.
const SLEEVE_COLOR := Color(0.30, 0.33, 0.24)
const GLOVE_COLOR := Color(0.13, 0.13, 0.12)

var skeleton: Skeleton3D
var ik: ArmIK
var _mesh: MeshInstance3D


func _init() -> void:
	name = "Arms"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var model: Node3D = MANNEQUIN.instantiate() as Node3D
	add_child(model)
	# Манекен смотрит в +Z, а камера — в −Z.
	model.rotation.y = PI
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_mesh = model.find_child("Mannequin", true, false) as MeshInstance3D
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		player.queue_free()
	_mesh.mesh = _cut_arms(_mesh.mesh as ArrayMesh, skeleton)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = ViewmodelLayer.VISUAL_LAYER
	_mesh.set_surface_override_material(0, _make_material(SLEEVE_COLOR))
	if _mesh.mesh.get_surface_count() > 1:
		_mesh.set_surface_override_material(1, _make_material(GLOVE_COLOR))
	# Без «расширения» рамки меш иногда отсекается: кости уезжают далеко от покоя.
	_mesh.extra_cull_margin = 2.0

	ik = ArmIK.new()
	ik.name = "ArmIK"
	skeleton.add_child(ik)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	for arm: ArmIK.Arm in [ik.right, ik.left]:
		arm.enabled = true
		arm.shoulder_override = true
	ik.right.curl = 1.15
	ik.right.thumb_curl = 0.9
	ik.left.curl = 0.45
	ik.left.thumb_curl = 0.4


## Поставить кисти на ствол и обновить скелет. gun — модель у этой же камеры.
## Вызывать каждый кадр после того, как ствол поставлен.
func solve(gun: GunView, delta: float) -> void:
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse()
	var gun_xform: Transform3D = gun.global_transform
	var camera_basis: Basis = get_parent_node_3d().global_transform.basis
	var data: WeaponData = gun.weapon

	_place_hand(ik.right, false, to_skeleton, gun_xform, data.grip_right, data.grip_right_fingers,
			Vector3.LEFT)
	_place_hand(ik.left, true, to_skeleton, gun_xform, data.grip_left, data.grip_left_fingers,
			data.grip_left_palm)
	# Ствол стоит на GunView.REACH дальше от глаза, а плечи — нет: руки вытянуты.
	var reach_back: Vector3 = camera_basis * Vector3(0.0, 0.0, GunView.REACH)
	ik.right.shoulder = to_skeleton * (gun_xform * data.shoulder_right + reach_back)
	ik.left.shoulder = to_skeleton * (gun_xform * data.shoulder_left + reach_back)
	ik.right.pole = (to_skeleton.basis * (camera_basis * POLE_RIGHT)).normalized()
	ik.left.pole = (to_skeleton.basis * (camera_basis * POLE_LEFT)).normalized()
	skeleton.advance(delta)


func _place_hand(arm: ArmIK.Arm, is_left: bool, to_skeleton: Transform3D, gun_xform: Transform3D,
		grip: Vector3, fingers: Vector3, palm: Vector3) -> void:
	var basis_global: Basis = ArmIK.hand_basis(gun_xform.basis * fingers, gun_xform.basis * palm, is_left)
	var palm_point: Vector3 = gun_xform * grip
	var wrist: Vector3 = ArmIK.wrist_for_palm(palm_point, basis_global, is_left)
	arm.target = to_skeleton * Transform3D(basis_global, wrist)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


## Новый меш из тех же вершин, но только с треугольниками рук.
static func _cut_arms(source: ArrayMesh, skel: Skeleton3D) -> ArrayMesh:
	var keep_bone := PackedByteArray()
	keep_bone.resize(skel.get_bone_count())
	for bone: int in skel.get_bone_count():
		var bone_name: String = skel.get_bone_name(bone)
		for prefix: String in ARM_BONE_PREFIXES:
			if bone_name.begins_with(prefix):
				keep_bone[bone] = 1
	var result := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per_vertex: int = bones.size() / maxi(vertex_count, 1)
		# Вершина «рука», если почти весь её вес — на костях руки (иначе часть
		# вершины останется привязанной к телу и вытянется «шипом»).
		var is_arm := PackedByteArray()
		is_arm.resize(vertex_count)
		for vertex: int in vertex_count:
			var arm_weight: float = 0.0
			for k: int in per_vertex:
				var i: int = vertex * per_vertex + k
				if keep_bone[bones[i]] == 1:
					arm_weight += weights[i]
			is_arm[vertex] = 1 if arm_weight > 0.97 else 0
		var kept := PackedInt32Array()
		for tri: int in range(0, indices.size(), 3):
			if is_arm[indices[tri]] == 1 and is_arm[indices[tri + 1]] == 1 and is_arm[indices[tri + 2]] == 1:
				kept.append(indices[tri])
				kept.append(indices[tri + 1])
				kept.append(indices[tri + 2])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags: int = source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	return result
