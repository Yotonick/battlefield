class_name HitMath
## Попадания пуль в бойцов считаются математически (луч против капсулы
## и сферы), а не через физический движок. Так хост может проверить
## попадание по бойцу «в прошлом» (компенсация пинга), не двигая тела.

## Хитбоксы относительно ног бойца. Тело — капсула по оси, голова — шар.
const BODY_RADIUS: float = 0.3
const STAND_BODY_BOTTOM: float = 0.32
const STAND_BODY_TOP: float = 1.3
const STAND_HEAD_Y: float = 1.62
const CROUCH_BODY_BOTTOM: float = 0.32
const CROUCH_BODY_TOP: float = 0.72
const CROUCH_HEAD_Y: float = 1.0
const HEAD_RADIUS: float = 0.15
## Дальше этого от луча боец точно не задет (быстрый отсев).
const BROAD_RADIUS: float = 1.3


## Расстояние вдоль луча до попадания в бойца или -1.
## ro — начало, rd — нормализованное направление, max_dist — длина отрезка.
## В result_headshot[0] пишется true, если первой задета голова.
static func ray_vs_soldier(ro: Vector3, rd: Vector3, max_dist: float,
		feet: Vector3, crouched: bool, result_headshot: Array[bool]) -> float:
	var center: Vector3 = feet + Vector3.UP * 0.9
	# Быстрый отсев: ближайшая к центру точка отрезка.
	var t_center: float = clampf((center - ro).dot(rd), 0.0, max_dist)
	if (ro + rd * t_center).distance_to(center) > BROAD_RADIUS:
		return -1.0

	var head_y: float = CROUCH_HEAD_Y if crouched else STAND_HEAD_Y
	var body_bottom: float = CROUCH_BODY_BOTTOM if crouched else STAND_BODY_BOTTOM
	var body_top: float = CROUCH_BODY_TOP if crouched else STAND_BODY_TOP

	var t_head: float = ray_sphere(ro, rd, feet + Vector3.UP * head_y, HEAD_RADIUS)
	var t_body: float = ray_capsule(ro, rd, feet + Vector3.UP * body_bottom,
			feet + Vector3.UP * body_top, BODY_RADIUS)
	var best: float = -1.0
	var headshot: bool = false
	if t_head >= 0.0 and t_head <= max_dist:
		best = t_head
		headshot = true
	if t_body >= 0.0 and t_body <= max_dist and (best < 0.0 or t_body < best):
		best = t_body
		headshot = false
	result_headshot[0] = headshot
	return best


## Луч против шара. -1, если мимо. Если начало внутри шара — 0.
static func ray_sphere(ro: Vector3, rd: Vector3, center: Vector3, radius: float) -> float:
	var oc: Vector3 = ro - center
	var b: float = oc.dot(rd)
	var c: float = oc.dot(oc) - radius * radius
	if c <= 0.0:
		return 0.0
	var h: float = b * b - c
	if h < 0.0:
		return -1.0
	var t: float = -b - sqrt(h)
	return t if t >= 0.0 else -1.0


## Луч против капсулы (отрезок pa–pb с радиусом r). -1, если мимо.
static func ray_capsule(ro: Vector3, rd: Vector3, pa: Vector3, pb: Vector3, r: float) -> float:
	var ba: Vector3 = pb - pa
	var oa: Vector3 = ro - pa
	var baba: float = ba.dot(ba)
	var bard: float = ba.dot(rd)
	var baoa: float = ba.dot(oa)
	var rdoa: float = rd.dot(oa)
	var oaoa: float = oa.dot(oa)
	var a: float = baba - bard * bard
	var b: float = baba * rdoa - baoa * bard
	var c: float = baba * oaoa - baoa * baoa - r * r * baba
	var h: float = b * b - a * c
	if a > 0.000001 and h >= 0.0:
		var t: float = (-b - sqrt(h)) / a
		var y: float = baoa + t * bard
		if y > 0.0 and y < baba and t >= 0.0:
			return t
	# Не попали в цилиндр — проверяем полусферы на концах.
	var t_a: float = ray_sphere(ro, rd, pa, r)
	var t_b: float = ray_sphere(ro, rd, pb, r)
	if t_a < 0.0:
		return t_b
	if t_b < 0.0:
		return t_a
	return minf(t_a, t_b)
