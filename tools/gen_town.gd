extends SceneTree
## Генератор greybox-карты «Городок» → res://maps/town/town.tscn
##
## Запуск (из папки проекта):
##   godot --headless --script res://tools/gen_town.gd
##
## Карта собирается из CSG-блоков, поэтому после генерации её можно спокойно
## править руками в редакторе. Но учтите: повторный запуск генератора
## ПЕРЕЗАПИШЕТ сцену. Либо правим генератор, либо сцену — не то и другое.
##
## Карта симметрична поворотом на 180° вокруг центра: западная половина
## (синие) строится функцией _build_half, восточная (красные) — это та же
## половина, повёрнутая на 180°. Так у команд одинаковые условия.
##
## Оси: X — запад(−)/восток(+), Z — север(−)/юг(+). Главная улица идёт по X
## (z = 0), поперечная — по Z (x = 0). Размер игровой зоны 152 × 88 м.

const OUT_PATH: String = "res://maps/town/town.tscn"
const SHADER: Shader = preload("res://shared/greybox/greybox_grid.gdshader")

## Граница игровой зоны (невидимые стены).
const BOUND_X: float = 76.0
const BOUND_Z: float = 44.0
## Слой «только для бойцов»: пули его не видят (BulletManager.WORLD_MASK = 1).
const PLAYER_ONLY_LAYER: int = 4

const WALL: float = 0.3
const FLOOR_HEIGHT: float = 3.3
const DOOR_SIZE := Vector2(1.2, 2.3)
const WINDOW_SIZE := Vector2(1.3, 1.1)
const WINDOW_SILL: float = 1.0
const RAMP_ANGLE_DEG: float = 24.0
const RAMP_WIDTH: float = 1.5

## Цвета greybox: [основной, линии сетки].
const COLORS: Dictionary[String, Array] = {
	"grass": [Color(0.42, 0.46, 0.33), Color(0.35, 0.39, 0.27)],
	"field": [Color(0.55, 0.5, 0.33), Color(0.47, 0.42, 0.27)],
	"road": [Color(0.27, 0.27, 0.27), Color(0.22, 0.22, 0.22)],
	"dirt": [Color(0.45, 0.39, 0.3), Color(0.38, 0.33, 0.25)],
	"sidewalk": [Color(0.55, 0.54, 0.5), Color(0.46, 0.45, 0.42)],
	"plaster": [Color(0.73, 0.69, 0.6), Color(0.6, 0.57, 0.49)],
	"plaster2": [Color(0.64, 0.66, 0.62), Color(0.52, 0.54, 0.5)],
	"brick": [Color(0.58, 0.4, 0.32), Color(0.47, 0.32, 0.26)],
	"roof": [Color(0.42, 0.27, 0.23), Color(0.34, 0.21, 0.18)],
	"floor": [Color(0.5, 0.44, 0.36), Color(0.42, 0.37, 0.3)],
	"wood": [Color(0.45, 0.35, 0.24), Color(0.36, 0.27, 0.18)],
	"stone": [Color(0.55, 0.55, 0.52), Color(0.45, 0.45, 0.42)],
	"concrete": [Color(0.62, 0.62, 0.6), Color(0.5, 0.5, 0.48)],
	"sandbag": [Color(0.56, 0.51, 0.38), Color(0.47, 0.42, 0.3)],
	"hay": [Color(0.78, 0.67, 0.36), Color(0.66, 0.56, 0.28)],
	"car": [Color(0.33, 0.37, 0.42), Color(0.27, 0.3, 0.35)],
	"car2": [Color(0.5, 0.2, 0.18), Color(0.42, 0.16, 0.14)],
	"wreck": [Color(0.22, 0.2, 0.19), Color(0.17, 0.15, 0.14)],
	"trunk": [Color(0.34, 0.26, 0.19), Color(0.28, 0.21, 0.15)],
	"crown": [Color(0.24, 0.34, 0.2), Color(0.2, 0.29, 0.16)],
	"metal": [Color(0.4, 0.42, 0.42), Color(0.33, 0.35, 0.35)],
}

var _root: Node3D
var _materials: Dictionary[String, ShaderMaterial] = {}
var _team: int = 1


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Town"
	_build_environment()
	_build_ground()
	_build_center()

	var west := _group(_root, "West", Transform3D.IDENTITY)
	_team = 1
	_build_half(west)
	var east := _group(_root, "East", Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	_team = 2
	_build_half(east)

	_build_bounds()
	_build_horizon()

	_set_owner_recursive(_root, _root)
	var scene := PackedScene.new()
	var error: Error = scene.pack(_root)
	if error != OK:
		push_error("pack: %s" % error_string(error))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	error = ResourceSaver.save(scene, OUT_PATH)
	print("[gen_town] сохранено %s (%s), узлов: %d" % [OUT_PATH, error_string(error), _count(_root)])
	_root.free()
	quit(0 if error == OK else 1)


# --- Окружение, земля, границы --------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42, 0.52, 0.64)
	sky_material.sky_horizon_color = Color(0.7, 0.72, 0.72)
	sky_material.ground_horizon_color = Color(0.7, 0.72, 0.72)
	sky_material.ground_bottom_color = Color(0.3, 0.31, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.68, 0.7)
	env.fog_density = 0.0035
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Солнце с юго-запада, ~40° над горизонтом: тени длинные, но не во всю улицу.
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), deg_to_rad(-140.0), 0.0)),
			Vector3(0, 30, 0))
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	_root.add_child(sun)


func _build_ground() -> void:
	var ground := _group(_root, "Ground", Transform3D.IDENTITY)
	_box(ground, "Grass", Vector3(0, -0.5, 0), Vector3(320, 1.0, 240), "grass")
	# Главная улица продолжается полевой дорогой до баз команд.
	_slab(ground, "MainRoad", Rect2(-50, -4, 100, 8), 0.02, "road")
	_slab(ground, "DirtRoadW", Rect2(-90, -3, 40, 6), 0.015, "dirt")
	_slab(ground, "DirtRoadE", Rect2(50, -3, 40, 6), 0.015, "dirt")
	_slab(ground, "CrossRoad", Rect2(-4, -48, 8, 96), 0.021, "road")


## Общее для обеих половин: перекрёсток в центре.
func _build_center() -> void:
	var center := _group(_root, "Center", Transform3D.IDENTITY)
	# Памятник на перекрёстке — укрытие в самом простреливаемом месте.
	_box(center, "MonumentBase", Vector3(0, 0.6, 0), Vector3(3.2, 1.2, 3.2), "stone")
	_box(center, "MonumentColumn", Vector3(0, 2.6, 0), Vector3(1.0, 2.8, 1.0), "stone")


func _build_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = PLAYER_ONLY_LAYER
	bounds.collision_mask = 0
	_root.add_child(bounds)
	var walls: Array[Array] = [
		[Vector3(-BOUND_X - 1.0, 10, 0), Vector3(2, 20, BOUND_Z * 2.0 + 4.0)],
		[Vector3(BOUND_X + 1.0, 10, 0), Vector3(2, 20, BOUND_Z * 2.0 + 4.0)],
		[Vector3(0, 10, -BOUND_Z - 1.0), Vector3(BOUND_X * 2.0 + 4.0, 20, 2)],
		[Vector3(0, 10, BOUND_Z + 1.0), Vector3(BOUND_X * 2.0 + 4.0, 20, 2)],
	]
	for i: int in walls.size():
		var shape := CollisionShape3D.new()
		shape.name = "Wall%d" % i
		var box := BoxShape3D.new()
		box.size = walls[i][1] as Vector3
		shape.shape = box
		shape.position = walls[i][0] as Vector3
		bounds.add_child(shape)


## Деревья и живые изгороди за границей — чтобы край карты не был обрывом.
func _build_horizon() -> void:
	var horizon := _group(_root, "Horizon", Transform3D.IDENTITY)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1944
	var index: int = 0
	var x: float = -BOUND_X - 4.0
	while x <= BOUND_X + 4.0:
		for side: float in [-1.0, 1.0]:
			var z: float = side * (BOUND_Z + 3.0 + rng.randf_range(0.0, 4.0))
			_tree(horizon, "TreeNS%d" % index, Vector3(x + rng.randf_range(-1.5, 1.5), 0, z),
					rng.randf_range(5.0, 8.0))
			index += 1
		x += rng.randf_range(5.0, 8.0)
	var z2: float = -BOUND_Z
	while z2 <= BOUND_Z:
		for side: float in [-1.0, 1.0]:
			var tx: float = side * (BOUND_X + 3.0 + rng.randf_range(0.0, 4.0))
			_tree(horizon, "TreeWE%d" % index, Vector3(tx, 0, z2 + rng.randf_range(-1.5, 1.5)),
					rng.randf_range(5.0, 8.0))
			index += 1
		z2 += rng.randf_range(5.0, 8.0)


# --- Половина карты --------------------------------------------------------

## Западная половина (для восточной её же поворачивают на 180°).
## _team — чьи точки спавна ставим.
func _build_half(half: Node3D) -> void:
	var streets := _group(half, "Streets", Transform3D.IDENTITY)
	# Тротуары вдоль главной улицы и поперечной (северная часть; южную даст поворот).
	_slab(streets, "WalkMainN", Rect2(-48, -5.5, 42.5, 1.5), 0.04, "sidewalk")
	_slab(streets, "WalkMainS", Rect2(-48, 4.0, 42.5, 1.5), 0.04, "sidewalk")
	_slab(streets, "WalkCrossW", Rect2(-5.5, -46, 1.5, 40.5), 0.04, "sidewalk")
	_slab(streets, "WalkCrossE", Rect2(4.0, -46, 1.5, 40.5), 0.04, "sidewalk")

	_build_north_block(_group(half, "NorthBlock", Transform3D.IDENTITY))
	_build_south_block(_group(half, "SouthBlock", Transform3D.IDENTITY))
	_build_street_cover(_group(half, "StreetCover", Transform3D.IDENTITY))
	_build_outskirts(_group(half, "Outskirts", Transform3D.IDENTITY))
	_build_base(_group(half, "Base", Transform3D.IDENTITY))


## Северный квартал: x −46…−7, z −22…−7, фасады на главную улицу (юг).
func _build_north_block(block: Node3D) -> void:
	_house(block, "HouseA", Vector3(-40, 0, -14), 8, 8, 1, [["s", 1.5], ["e", 2.0]], "plaster")
	_house(block, "TwoStorey", Vector3(-26, 0, -14), 10, 8, 2, [["s", 2.5], ["e", 1.0]], "brick", "n")
	_house(block, "HouseB", Vector3(-12.5, 0, -13.5), 7, 7, 1, [["s", -1.0], ["e", 1.0], ["n", 1.5]], "plaster2")
	# Мебель — укрытия внутри.
	_box(block, "TableA", Vector3(-41.5, 0.45, -16.5), Vector3(1.8, 0.9, 0.9), "wood")
	_box(block, "TableB", Vector3(-12.5, 0.45, -12.0), Vector3(0.9, 0.9, 1.8), "wood")
	_box(block, "CabinetTwo", Vector3(-22.5, 0.75, -11.5), Vector3(1.6, 1.5, 0.6), "wood")
	_box(block, "TableTwoUp", Vector3(-27.5, FLOOR_HEIGHT + 0.45, -12.5), Vector3(1.8, 0.9, 0.9), "wood")

	# Дворы за домами: низкие заборы (через 0.8 м можно перепрыгнуть),
	# сарай, поленница.
	_fence_line(block, "YardFenceN", Vector3(-46, 0, -24), Vector3(-8, 0, -24), [-35.0, -19.0])
	_fence_line(block, "YardFenceW", Vector3(-46, 0, -24), Vector3(-46, 0, -8), [-16.0])
	_fence_line(block, "YardDivide", Vector3(-33, 0, -24), Vector3(-33, 0, -18.5), [])
	_shed(block, "Shed", Vector3(-38, 0, -21.5))
	_box(block, "Woodpile", Vector3(-17, 0.55, -21.5), Vector3(3.0, 1.1, 1.0), "wood")
	_tree(block, "YardTree1", Vector3(-30, 0, -21), 6.5, true)
	_tree(block, "YardTree2", Vector3(-9, 0, -20.5), 5.5, true)


## Южный квартал: x −46…−7, z 7…22, фасады на главную улицу (север).
func _build_south_block(block: Node3D) -> void:
	_house(block, "HouseC", Vector3(-39, 0, 13.5), 9, 7, 1, [["n", -1.5], ["w", 0.0]], "plaster2")
	_shop(block, "Shop", Vector3(-24, 0, 13.0))
	_ruins(block, "Ruins", Vector3(-11.5, 0, 14.0))
	_box(block, "TableC", Vector3(-41.0, 0.45, 15.0), Vector3(1.8, 0.9, 0.9), "wood")

	_fence_line(block, "YardFenceS", Vector3(-46, 0, 23), Vector3(-8, 0, 23), [-40.0, -26.0, -14.0])
	_stone_wall(block, "GardenWall", Vector3(-31.5, 0, 17.5), Vector3(-31.5, 0, 23), 1.0)
	_tree(block, "GardenTree", Vector3(-35, 0, 20.5), 6.0, true)


## Укрытия на улицах: машины, бетонные блоки, мешки.
func _build_street_cover(cover: Node3D) -> void:
	_car(cover, "Car1", Vector3(-34, 0, -2.2), 0.0, "car")
	_car(cover, "Car2", Vector3(-17, 0, 2.3), 0.12, "car2")
	_car(cover, "WreckCross", Vector3(-1.8, 0, -16), PI * 0.5 + 0.35, "wreck")
	_car(cover, "Car3", Vector3(2.2, 0, -32), PI * 0.5, "car")
	# Блокпост на въезде в городок со стороны базы.
	_box(cover, "Barrier1", Vector3(-49, 0.45, -2.0), Vector3(0.6, 0.9, 3.0), "concrete")
	_box(cover, "Barrier2", Vector3(-47.5, 0.45, 2.6), Vector3(0.6, 0.9, 3.0), "concrete")
	_sandbags(cover, "Sandbags1", Vector3(-8.5, 0, -5.8), 4.0, 0.0)
	_sandbags(cover, "Sandbags2", Vector3(-5.8, 0, -27), 3.0, PI * 0.5)
	# Остановка у дороги.
	_box(cover, "BusStopBack", Vector3(-28, 1.1, 5.9), Vector3(3.0, 2.2, 0.12), "metal")
	_box(cover, "BusStopRoof", Vector3(-28, 2.3, 5.4), Vector3(3.2, 0.1, 1.3), "metal")
	_box(cover, "Crates1", Vector3(-6.5, 0.6, 9.5), Vector3(1.2, 1.2, 1.2), "wood")
	_box(cover, "Crates2", Vector3(-6.4, 1.6, 9.4), Vector3(0.8, 0.8, 0.8), "wood")
	_box(cover, "Crates3", Vector3(-7.7, 0.45, 10.4), Vector3(0.9, 0.9, 0.9), "wood")


## Окраины между городком и базой: поле, стога, каменная стена, трактор.
func _build_outskirts(outskirts: Node3D) -> void:
	_slab(outskirts, "FieldS", Rect2(-74, 26, 66, 17), 0.01, "field")
	_slab(outskirts, "FieldN", Rect2(-74, -43, 30, 16), 0.01, "field")
	_stone_wall(outskirts, "FieldWallS", Vector3(-62, 0, 25.5), Vector3(-10, 0, 25.5), 1.0, [-48.0, -30.0, -18.0])
	_stone_wall(outskirts, "TownWallW", Vector3(-53, 0, -26), Vector3(-53, 0, -7), 1.0, [-17.0])
	_stone_wall(outskirts, "TownWallW2", Vector3(-53, 0, 7), Vector3(-53, 0, 24), 1.0, [15.0])
	for i: int in 6:
		var pos := Vector3(-66.0 + float(i % 3) * 14.0, 0, 31.0 + float(i / 3) * 7.0)
		_hay_bale(outskirts, "Hay%d" % i, pos + Vector3(float(i) * 0.7, 0, 0))
	_hay_bale(outskirts, "HayN1", Vector3(-62, 0, -33))
	_hay_bale(outskirts, "HayN2", Vector3(-52, 0, -38))
	_tractor(outskirts, "Tractor", Vector3(-38, 0, 35), 0.4)
	_tree(outskirts, "FieldTree1", Vector3(-24, 0, 38), 7.0, true)
	_tree(outskirts, "FieldTree2", Vector3(-58, 0, -30), 6.5, true)
	_tree(outskirts, "RoadTree1", Vector3(-55, 0, -6.2), 6.0, true)
	_tree(outskirts, "RoadTree2", Vector3(-60, 0, 6.5), 6.5, true)


## База команды: ферма на краю карты, точки спавна.
func _build_base(base: Node3D) -> void:
	_barn(base, "Barn", Vector3(-64, 0, -17))
	_box(base, "SupplyCrates1", Vector3(-60.5, 0.6, 15.0), Vector3(2.4, 1.2, 1.2), "wood")
	_box(base, "SupplyCrates2", Vector3(-63.5, 0.6, 15.5), Vector3(1.2, 1.2, 1.2), "wood")
	_sandbags(base, "BaseSandbags", Vector3(-58, 0, 11.5), 5.0, 0.0)

	var spawns := _group(base, "SpawnPoints", Transform3D.IDENTITY)
	var group_name: String = "spawn_team_%d" % _team
	# Лицом на восток, к городку (yaw −90°).
	var facing := Basis(Vector3.UP, -PI * 0.5)
	var index: int = 0
	for row: int in 2:
		for col: int in 5:
			var marker := Marker3D.new()
			marker.name = "Spawn%d" % index
			marker.transform = Transform3D(facing, Vector3(-70.0 + float(row) * 3.0, 0.05, -8.0 + float(col) * 4.0))
			marker.add_to_group(group_name, true)
			spawns.add_child(marker)
			index += 1


# --- Постройки ------------------------------------------------------------

## Дом-коробка с дверями и окнами. center — центр на уровне земли.
## doors: [[сторона, смещение], …]; стороны: "n" (−Z), "s" (+Z), "w" (−X), "e" (+X).
## Для двух этажей внутри перекрытие и пандус вдоль стены ramp_side ("n"/"s").
func _house(parent: Node3D, house_name: String, center: Vector3, w: float, d: float, floors: int,
		doors: Array, material: String, ramp_side: String = "n") -> void:
	var height: float = FLOOR_HEIGHT * float(floors) + WALL
	var shell := _box(parent, house_name, center + Vector3(0, height * 0.5, 0), Vector3(w, height, d), material)
	# Внутренний объём: пол — это земля, сверху остаётся крыша толщиной WALL.
	var inner_h: float = height - WALL + 0.1
	_cut(shell, "Inner", Vector3(0, -height * 0.5 + inner_h * 0.5 - 0.1, 0),
			Vector3(w - WALL * 2.0, inner_h, d - WALL * 2.0))

	var door_spots: Dictionary[String, Array] = {"n": [], "s": [], "w": [], "e": []}
	for door: Array in doors:
		var side: String = door[0]
		var offset: float = door[1]
		door_spots[side].append(offset)
		_wall_hole(shell, "Door_%s_%d" % [side, int(offset * 10.0)], side, offset,
				DOOR_SIZE.y * 0.5 - 0.05, Vector2(DOOR_SIZE.x, DOOR_SIZE.y + 0.1), w, d, height)

	for floor_index: int in floors:
		var sill: float = WINDOW_SILL + FLOOR_HEIGHT * float(floor_index)
		for side: String in ["n", "s", "w", "e"]:
			var wall_len: float = w if side == "n" or side == "s" else d
			var skip: Array = door_spots[side] if floor_index == 0 else []
			# У двухэтажного вдоль стены с пандусом окна первого этажа не делаем.
			if floors == 2 and floor_index == 0 and side == ramp_side:
				continue
			for offset: float in _window_offsets(wall_len, skip):
				_wall_hole(shell, "Win_%s_%d_%d" % [side, floor_index, int(offset * 10.0)], side, offset,
						sill + WINDOW_SIZE.y * 0.5, WINDOW_SIZE, w, d, height)

	# Крыша-козырёк чуть шире стен.
	_box(parent, house_name + "Roof", center + Vector3(0, height + 0.1, 0), Vector3(w + 0.6, 0.2, d + 0.6), "roof")
	if floors == 2:
		_upper_floor(parent, house_name, center, w, d, ramp_side)


## Позиции окон вдоль стены (от центра), с пропуском мест под двери.
func _window_offsets(wall_len: float, doors: Array) -> Array[float]:
	var result: Array[float] = []
	var usable: float = wall_len - 2.6
	if usable < 0.5:
		return result
	var count: int = maxi(1, int(usable / 2.8) + 1)
	for i: int in count:
		var t: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var offset: float = -usable * 0.5 + usable * t
		var clash: bool = false
		for door_offset: float in doors:
			if absf(offset - door_offset) < (DOOR_SIZE.x + WINDOW_SIZE.x) * 0.5 + 0.5:
				clash = true
		if not clash:
			result.append(offset)
	return result


## Проём в стене коробки shell. y — высота центра проёма от земли.
func _wall_hole(shell: CSGBox3D, hole_name: String, side: String, offset: float, y: float,
		size: Vector2, w: float, d: float, height: float) -> void:
	var local_y: float = y - height * 0.5
	var depth: float = WALL * 3.0
	match side:
		"n":
			_cut(shell, hole_name, Vector3(offset, local_y, -d * 0.5), Vector3(size.x, size.y, depth))
		"s":
			_cut(shell, hole_name, Vector3(offset, local_y, d * 0.5), Vector3(size.x, size.y, depth))
		"w":
			_cut(shell, hole_name, Vector3(-w * 0.5, local_y, offset), Vector3(depth, size.y, size.x))
		"e":
			_cut(shell, hole_name, Vector3(w * 0.5, local_y, offset), Vector3(depth, size.y, size.x))


## Перекрытие второго этажа с проёмом и пандус вдоль стены ramp_side.
## Ступенек нет специально: у бойца нет автоподъёма на ступени.
func _upper_floor(parent: Node3D, house_name: String, center: Vector3, w: float, d: float,
		ramp_side: String) -> void:
	var angle: float = deg_to_rad(RAMP_ANGLE_DEG)
	var run: float = FLOOR_HEIGHT / tan(angle)
	var inner_w: float = w - WALL * 2.0
	var inner_d: float = d - WALL * 2.0
	var x0: float = -inner_w * 0.5 + 1.0
	var x1: float = x0 + run
	var z_sign: float = -1.0 if ramp_side == "n" else 1.0
	var strip_center_z: float = z_sign * (inner_d * 0.5 - RAMP_WIDTH * 0.5)
	var strip_inner_z: float = z_sign * (inner_d * 0.5 - RAMP_WIDTH)

	var slab := _box(parent, house_name + "Floor2", center + Vector3(0, FLOOR_HEIGHT - 0.125, 0),
			Vector3(inner_w, 0.25, inner_d), "floor")
	_cut(slab, "StairHole", Vector3((x0 - 0.1 + x1) * 0.5, 0, strip_center_z),
			Vector3(x1 - x0 + 0.1, 1.0, RAMP_WIDTH + 0.02))

	# Пандус: верхняя плоскость проходит через (x0, 0) и (x1, FLOOR_HEIGHT).
	var thickness: float = 0.3
	var length: float = run / cos(angle)
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var mid := Vector3((x0 + x1) * 0.5, FLOOR_HEIGHT * 0.5, strip_center_z)
	var ramp := _box(parent, house_name + "Ramp", center + mid - normal * (thickness * 0.5),
			Vector3(length, thickness, RAMP_WIDTH), "wood")
	ramp.basis = Basis(Vector3.BACK, angle)

	# Перила вокруг проёма (кроме выхода с пандуса — со стороны x1).
	var rail_y: float = FLOOR_HEIGHT + 0.45
	_box(parent, house_name + "RailLong", center + Vector3((x0 + x1) * 0.5, rail_y, strip_inner_z),
			Vector3(x1 - x0, 0.9, 0.1), "wood")
	_box(parent, house_name + "RailEnd", center + Vector3(x0 - 0.05, rail_y, strip_center_z),
			Vector3(0.1, 0.9, RAMP_WIDTH), "wood")

	# Для автотеста карты: точка у подножия пандуса и ожидаемая высота наверху.
	var marker := Marker3D.new()
	marker.name = house_name + "RampTest"
	marker.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), center + Vector3(x0 - 0.45, 0.05, strip_center_z))
	marker.set_meta(&"top_height", FLOOR_HEIGHT)
	marker.add_to_group(&"test_ramp", true)
	parent.add_child(marker)


## Магазин: широкие витрины на улицу, двери спереди и сзади, прилавок.
func _shop(parent: Node3D, shop_name: String, center: Vector3) -> void:
	var w: float = 12.0
	var d: float = 8.0
	var height: float = 3.8
	var shell := _box(parent, shop_name, center + Vector3(0, height * 0.5, 0), Vector3(w, height, d), "plaster")
	_cut(shell, "Inner", Vector3(0, -0.2, 0), Vector3(w - WALL * 2.0, height - WALL + 0.1, d - WALL * 2.0))
	_wall_hole(shell, "Door_n", "n", 0.0, DOOR_SIZE.y * 0.5 - 0.05, Vector2(1.6, DOOR_SIZE.y + 0.1), w, d, height)
	_wall_hole(shell, "Door_s", "s", 3.5, DOOR_SIZE.y * 0.5 - 0.05, Vector2(DOOR_SIZE.x, DOOR_SIZE.y + 0.1), w, d, height)
	for offset: float in [-3.6, 3.6]:
		_wall_hole(shell, "Vitrine_%d" % int(offset), "n", offset, 1.7, Vector2(3.0, 1.8), w, d, height)
	_wall_hole(shell, "Win_w", "w", 0.0, 1.55, WINDOW_SIZE, w, d, height)
	_wall_hole(shell, "Win_e", "e", 0.0, 1.55, WINDOW_SIZE, w, d, height)
	_wall_hole(shell, "Win_s", "s", -2.5, 1.55, WINDOW_SIZE, w, d, height)
	_box(parent, shop_name + "Roof", center + Vector3(0, height + 0.1, 0), Vector3(w + 0.6, 0.2, d + 0.6), "roof")
	_box(parent, shop_name + "Counter", center + Vector3(-1.5, 0.55, 1.6), Vector3(5.0, 1.1, 0.7), "wood")
	_box(parent, shop_name + "Shelf1", center + Vector3(-4.5, 0.9, 3.3), Vector3(2.0, 1.8, 0.5), "wood")
	_box(parent, shop_name + "Shelf2", center + Vector3(0.5, 0.9, -1.0), Vector3(0.5, 1.8, 2.4), "wood")


## Развалины дома: стены разной высоты, без крыши, с проломами.
func _ruins(parent: Node3D, ruins_name: String, center: Vector3) -> void:
	var walls: Array[Array] = [
		# [центр (локально), размер]
		[Vector3(-1.5, 1.25, -3.5), Vector3(4.0, 2.5, WALL)],
		[Vector3(2.8, 0.6, -3.5), Vector3(1.4, 1.2, WALL)],
		[Vector3(-3.5, 1.0, 0.0), Vector3(WALL, 2.0, 7.0)],
		[Vector3(3.5, 1.6, 1.5), Vector3(WALL, 3.2, 4.0)],
		[Vector3(0.5, 0.5, 3.5), Vector3(6.0, 1.0, WALL)],
	]
	for i: int in walls.size():
		var wall := _box(parent, "%sWall%d" % [ruins_name, i], center + (walls[i][0] as Vector3),
				walls[i][1] as Vector3, "brick")
		if i == 0:
			_cut(wall, "Breach", Vector3(0.4, 0.3, 0), Vector3(1.3, 1.1, 1.0))
	_box(parent, ruins_name + "Rubble1", center + Vector3(1.0, 0.3, -1.0), Vector3(1.6, 0.6, 1.2), "stone")
	_box(parent, ruins_name + "Rubble2", center + Vector3(-1.8, 0.2, 1.8), Vector3(1.2, 0.4, 1.6), "stone")
	_box(parent, ruins_name + "Beam", center + Vector3(0.5, 0.25, 0.5), Vector3(4.5, 0.25, 0.3), "wood")


## Амбар на базе: открыт в сторону городка, внутри сено.
func _barn(parent: Node3D, barn_name: String, center: Vector3) -> void:
	var w: float = 9.0
	var d: float = 12.0
	var height: float = 5.0
	var shell := _box(parent, barn_name, center + Vector3(0, height * 0.5, 0), Vector3(w, height, d), "wood")
	_cut(shell, "Inner", Vector3(0, -0.2, 0), Vector3(w - WALL * 2.0, height - WALL + 0.1, d - WALL * 2.0))
	_wall_hole(shell, "Gate", "e", 0.0, 1.8, Vector2(5.0, 3.6), w, d, height)
	_wall_hole(shell, "Door_s", "s", 2.0, DOOR_SIZE.y * 0.5 - 0.05, Vector2(DOOR_SIZE.x, DOOR_SIZE.y + 0.1), w, d, height)
	_box(parent, barn_name + "Roof", center + Vector3(0, height + 0.1, 0), Vector3(w + 0.8, 0.2, d + 0.8), "roof")
	_box(parent, barn_name + "Hay1", center + Vector3(-2.5, 0.6, -3.5), Vector3(2.4, 1.2, 3.0), "hay")
	_box(parent, barn_name + "Hay2", center + Vector3(-2.8, 1.6, -3.8), Vector3(1.6, 0.8, 1.8), "hay")


## Сарай во дворе.
func _shed(parent: Node3D, shed_name: String, center: Vector3) -> void:
	var shell := _box(parent, shed_name, center + Vector3(0, 1.2, 0), Vector3(3.5, 2.4, 2.5), "wood")
	_cut(shell, "Inner", Vector3(0, -0.1, 0), Vector3(3.1, 2.3, 2.1))
	_wall_hole(shell, "Door", "s", 0.8, 1.0, Vector2(1.0, 2.1), 3.5, 2.5, 2.4)


func _car(parent: Node3D, car_name: String, pos: Vector3, yaw: float, material: String) -> void:
	var car := _group(parent, car_name, Transform3D(Basis(Vector3.UP, yaw), pos))
	_box(car, "Body", Vector3(0, 0.55, 0), Vector3(4.3, 0.8, 1.8), material)
	_box(car, "Cabin", Vector3(-0.3, 1.25, 0), Vector3(2.2, 0.65, 1.6), material)


func _tractor(parent: Node3D, tractor_name: String, pos: Vector3, yaw: float) -> void:
	var tractor := _group(parent, tractor_name, Transform3D(Basis(Vector3.UP, yaw), pos))
	_box(tractor, "Body", Vector3(0.4, 1.0, 0), Vector3(2.6, 1.0, 1.2), "car2")
	_box(tractor, "Cabin", Vector3(-0.6, 2.0, 0), Vector3(1.3, 1.2, 1.3), "metal")
	_box(tractor, "WheelL", Vector3(-0.9, 0.75, 0.85), Vector3(1.5, 1.5, 0.45), "wreck")
	_box(tractor, "WheelR", Vector3(-0.9, 0.75, -0.85), Vector3(1.5, 1.5, 0.45), "wreck")


func _sandbags(parent: Node3D, bags_name: String, pos: Vector3, length: float, yaw: float) -> void:
	var bags := _group(parent, bags_name, Transform3D(Basis(Vector3.UP, yaw), pos))
	_box(bags, "Bags", Vector3(0, 0.45, 0), Vector3(length, 0.9, 0.7), "sandbag")


func _hay_bale(parent: Node3D, bale_name: String, pos: Vector3) -> void:
	var bale := CSGCylinder3D.new()
	bale.name = bale_name
	bale.radius = 0.8
	bale.height = 1.4
	bale.sides = 12
	bale.use_collision = true
	bale.material = _material("hay")
	bale.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), pos + Vector3(0, 0.8, 0))
	parent.add_child(bale)


## Дерево: ствол (стоп для пуль и бойцов) и крона (без столкновений).
func _tree(parent: Node3D, tree_name: String, pos: Vector3, height: float, collide_trunk: bool = false) -> void:
	var trunk := CSGCylinder3D.new()
	trunk.name = tree_name
	trunk.radius = 0.25
	trunk.height = height * 0.45
	trunk.sides = 6
	trunk.use_collision = collide_trunk
	trunk.material = _material("trunk")
	trunk.position = pos + Vector3(0, height * 0.225, 0)
	parent.add_child(trunk)
	var crown := CSGCylinder3D.new()
	crown.name = tree_name + "Crown"
	crown.cone = true
	crown.radius = height * 0.3
	crown.height = height * 0.75
	crown.sides = 7
	crown.material = _material("crown")
	crown.position = pos + Vector3(0, height * 0.3 + height * 0.375, 0)
	parent.add_child(crown)


## Деревянный забор 0.8 м (перепрыгивается) с калитками-проходами.
func _fence_line(parent: Node3D, fence_name: String, from: Vector3, to: Vector3, gaps: Array) -> void:
	_segmented_wall(parent, fence_name, from, to, 0.8, 0.08, "wood", gaps, 1.4)


## Каменная стена ~1 м: укрытие сидя, стрелять можно поверх стоя.
func _stone_wall(parent: Node3D, wall_name: String, from: Vector3, to: Vector3, height: float,
		gaps: Array = []) -> void:
	_segmented_wall(parent, wall_name, from, to, height, 0.45, "stone", gaps, 2.0)


## Прямая стенка от from до to (по X или по Z) с проходами в точках gaps
## (координата вдоль стены).
func _segmented_wall(parent: Node3D, wall_name: String, from: Vector3, to: Vector3, height: float,
		thickness: float, material: String, gaps: Array, gap_width: float) -> void:
	var along_x: bool = absf(to.x - from.x) > absf(to.z - from.z)
	var a: float = minf(from.x, to.x) if along_x else minf(from.z, to.z)
	var b: float = maxf(from.x, to.x) if along_x else maxf(from.z, to.z)
	var cuts: Array[float] = []
	for gap: float in gaps:
		cuts.append(gap)
	cuts.sort()
	var pieces: Array[Vector2] = []
	var start: float = a
	for gap: float in cuts:
		pieces.append(Vector2(start, gap - gap_width * 0.5))
		start = gap + gap_width * 0.5
	pieces.append(Vector2(start, b))
	for i: int in pieces.size():
		var piece: Vector2 = pieces[i]
		var length: float = piece.y - piece.x
		if length < 0.2:
			continue
		var mid: float = (piece.x + piece.y) * 0.5
		var pos: Vector3 = Vector3(mid, height * 0.5, from.z) if along_x else Vector3(from.x, height * 0.5, mid)
		var size: Vector3 = Vector3(length, height, thickness) if along_x else Vector3(thickness, height, length)
		_box(parent, "%s%d" % [wall_name, i], pos, size, material)


# --- Примитивы ------------------------------------------------------------

func _group(parent: Node, group_name: String, xform: Transform3D) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	node.transform = xform
	parent.add_child(node)
	return node


## Корневой CSG-блок со столкновениями (слой 1 — его видят и бойцы, и пули).
func _box(parent: Node, box_name: String, center: Vector3, size: Vector3, material: String) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = box_name
	box.size = size
	box.position = center
	box.material = _material(material)
	box.use_collision = true
	parent.add_child(box)
	return box


## Плоская полоса на земле (дорога, тротуар): Rect2 по XZ, высота верха top.
func _slab(parent: Node, slab_name: String, rect: Rect2, top: float, material: String) -> void:
	var thickness: float = 0.1
	_box(parent, slab_name, Vector3(rect.position.x + rect.size.x * 0.5, top - thickness * 0.5,
			rect.position.y + rect.size.y * 0.5), Vector3(rect.size.x, thickness, rect.size.y), material)


## Вырез внутри CSG-блока (координаты локальные).
func _cut(parent: CSGBox3D, cut_name: String, local_center: Vector3, size: Vector3) -> void:
	var cut := CSGBox3D.new()
	cut.name = cut_name
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	cut.size = size
	cut.position = local_center
	cut.material = parent.material
	parent.add_child(cut)


func _material(key: String) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var colors: Array = COLORS[key]
	material.set_shader_parameter(&"base_color", colors[0])
	material.set_shader_parameter(&"line_color", colors[1])
	material.resource_name = key
	_materials[key] = material
	return material


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)


func _count(node: Node) -> int:
	var total: int = 1
	for child: Node in node.get_children():
		total += _count(child)
	return total
