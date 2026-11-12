class_name ArmIK
extends SkeletonModifier3D
## IK двух рук манекена Quaternius: плечо–предплечье–кисть тянутся к заданному
## положению кисти, пальцы сгибаются (хват). Один и тот же код — для рук от
## первого лица и для чужого бойца.
##
## Цели задаются в координатах скелета (Skeleton3D), чтобы не зависеть от того,
## где висит модель. Обновлять цели — до skeleton.advance() (режим MANUAL)
## или до обычного обновления скелета.

## Одна рука.
class Arm:
	var enabled: bool = false
	## Кисть: origin — запястье, basis — поворот кости кисти (см. hand_basis).
	var target: Transform3D = Transform3D.IDENTITY
	## Направление, куда «смотрит» локоть (в координатах скелета).
	var pole: Vector3 = Vector3.DOWN
	## Своё положение плеча (только для рук от первого лица — меш без тела).
	var shoulder_override: bool = false
	var shoulder: Vector3 = Vector3.ZERO
	## Сгиб пальцев, радианы на сустав (0 — прямые).
	var curl: float = 0.0
	var thumb_curl: float = 0.0

	var upper: int = -1
	var fore: int = -1
	var hand: int = -1
	var len_upper: float = 0.0
	var len_fore: float = 0.0
	## [кость, множитель сгиба]
	var fingers: Array[Vector2i] = []
	var thumbs: Array[int] = []

const FINGER_NAMES: Array[String] = ["f_index", "f_middle", "f_ring", "f_pinky"]
## Доля сгиба по суставам пальца (01 — у ладони).
const JOINT_SHARE: Array[float] = [0.8, 1.0, 0.7]
## От запястья до середины ладони вдоль кисти, м.
const PALM_FROM_WRIST: float = 0.075
## Наибольший угол между кистью и предплечьем, радианы — чтобы кисть
## не «ломалась», даже если хват задан неудачно.
const MAX_WRIST_BEND: float = deg_to_rad(80.0)
## От середины ладони (кость) до её поверхности, м.
const PALM_THICKNESS: float = 0.022

var right := Arm.new()
var left := Arm.new()
var _ready_bones: bool = false


## Поворот кости кисти. fingers — куда направлены пальцы (от запястья к костяшкам),
## palm — куда смотрит ладонь. Оси кости кисти у манекена: Y — к пальцам,
## Z — в сторону большого пальца, X — тыльная сторона у правой и ладонь у левой.
static func hand_basis(fingers: Vector3, palm: Vector3, is_left: bool) -> Basis:
	var y: Vector3 = fingers.normalized()
	var x: Vector3 = (palm if is_left else -palm)
	x = (x - y * x.dot(y)).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


## Где должно быть запястье, чтобы середина ладони легла на точку хвата.
static func wrist_for_palm(palm_point: Vector3, basis: Basis, is_left: bool) -> Vector3:
	var palm_normal: Vector3 = basis.x if is_left else -basis.x
	return palm_point - basis.y * PALM_FROM_WRIST - palm_normal * PALM_THICKNESS


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if not _ready_bones:
		_ready_bones = true
		_find_bones(skeleton, right, "R")
		_find_bones(skeleton, left, "L")
	for arm: Arm in [right, left]:
		if arm.enabled and arm.upper >= 0:
			_solve(skeleton, arm)
			_curl_fingers(skeleton, arm)


func _find_bones(skeleton: Skeleton3D, arm: Arm, side: String) -> void:
	arm.upper = skeleton.find_bone("DEF-upper_arm." + side)
	arm.fore = skeleton.find_bone("DEF-forearm." + side)
	arm.hand = skeleton.find_bone("DEF-hand." + side)
	if arm.upper < 0 or arm.fore < 0 or arm.hand < 0:
		push_warning("ArmIK: нет костей руки " + side)
		arm.upper = -1
		return
	var rest_upper: Vector3 = skeleton.get_bone_global_rest(arm.upper).origin
	var rest_fore: Vector3 = skeleton.get_bone_global_rest(arm.fore).origin
	var rest_hand: Vector3 = skeleton.get_bone_global_rest(arm.hand).origin
	arm.len_upper = rest_upper.distance_to(rest_fore)
	arm.len_fore = rest_fore.distance_to(rest_hand)
	for finger: String in FINGER_NAMES:
		for joint: int in 3:
			var bone: int = skeleton.find_bone("DEF-%s.0%d.%s" % [finger, joint + 1, side])
			if bone >= 0:
				arm.fingers.append(Vector2i(bone, joint))
	for joint: int in 3:
		var thumb: int = skeleton.find_bone("DEF-thumb.0%d.%s" % [joint + 1, side])
		if thumb >= 0:
			arm.thumbs.append(thumb)


func _solve(skeleton: Skeleton3D, arm: Arm) -> void:
	var upper_pose: Transform3D = skeleton.get_bone_global_pose(arm.upper)
	if arm.shoulder_override:
		upper_pose.origin = arm.shoulder
	var shoulder: Vector3 = upper_pose.origin
	var target: Vector3 = arm.target.origin
	var to_target: Vector3 = target - shoulder
	var reach: float = arm.len_upper + arm.len_fore
	var dist: float = clampf(to_target.length(), 0.01, reach * 0.999)
	var dir: Vector3 = to_target.normalized() if to_target.length() > 0.0001 else Vector3.FORWARD

	# Плоскость сгиба: направление на локоть, перпендикулярное линии плечо–кисть.
	var bend: Vector3 = arm.pole - dir * arm.pole.dot(dir)
	if bend.length() < 0.0001:
		bend = Vector3.DOWN - dir * dir.y
	bend = bend.normalized()
	var cos_a: float = clampf((arm.len_upper * arm.len_upper + dist * dist
			- arm.len_fore * arm.len_fore) / (2.0 * arm.len_upper * dist), -1.0, 1.0)
	var elbow: Vector3 = shoulder + dir * arm.len_upper * cos_a \
			+ bend * arm.len_upper * sqrt(1.0 - cos_a * cos_a)
	var wrist: Vector3 = shoulder + dir * dist
	# Ось локтевого сгиба одна для плеча и предплечья — так рука не «скручивается».
	var hinge: Vector3 = bend.cross(dir).normalized()

	upper_pose.basis = _aim(elbow - shoulder, hinge)
	skeleton.set_bone_global_pose(arm.upper, upper_pose)

	var fore_pose := Transform3D(_aim(wrist - elbow, hinge), elbow)
	skeleton.set_bone_global_pose(arm.fore, fore_pose)

	var hand_basis_target: Basis = _limit_wrist(arm.target.basis.orthonormalized(), (wrist - elbow).normalized())
	var hand_pose := Transform3D(hand_basis_target, wrist)
	skeleton.set_bone_global_pose(arm.hand, hand_pose)


## Поворачивает кисть к линии предплечья, если угол между ними больше MAX_WRIST_BEND.
static func _limit_wrist(hand: Basis, forearm_dir: Vector3) -> Basis:
	var along: Vector3 = hand.y.normalized()
	var angle: float = along.angle_to(forearm_dir)
	if angle <= MAX_WRIST_BEND:
		return hand
	var axis: Vector3 = along.cross(forearm_dir)
	if axis.length() < 0.0001:
		return hand
	return Basis(axis.normalized(), angle - MAX_WRIST_BEND) * hand


## Базис кости: Y — вдоль кости, X — ось сгиба локтя.
static func _aim(along: Vector3, hinge: Vector3) -> Basis:
	var y: Vector3 = along.normalized()
	var x: Vector3 = (hinge - y * hinge.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _curl_fingers(skeleton: Skeleton3D, arm: Arm) -> void:
	for finger: Vector2i in arm.fingers:
		var rest: Quaternion = skeleton.get_bone_rest(finger.x).basis.get_rotation_quaternion()
		var angle: float = arm.curl * JOINT_SHARE[finger.y]
		skeleton.set_bone_pose_rotation(finger.x, rest * Quaternion(Vector3.RIGHT, angle))
	for index: int in arm.thumbs.size():
		var bone: int = arm.thumbs[index]
		var rest_thumb: Quaternion = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var thumb_angle: float = arm.thumb_curl * (0.3 if index == 0 else 0.8)
		skeleton.set_bone_pose_rotation(bone, rest_thumb * Quaternion(Vector3.RIGHT, thumb_angle))
