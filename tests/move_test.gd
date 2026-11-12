extends Node
## Тест движения бойца на полигоне: лестницы 17/25 см (вверх, вниз, бегом, в присяде),
## пандусы 25°/50°, ящик 0.5 м. Печатает высоту, тики «в воздухе» (кроме падений с края)
## и тики с потерей скорости. Запуск: godot --headless --path . res://tests/move_test.tscn
var player: Player
var frames: int = 0
var case_idx: int = 0
var max_y: float = 0.0
var air_ticks: int = 0
var stalls: int = 0
func top_of(i: int) -> float:
	return [0.0, 1.36, 1.75, 3.2, 0.0, 0.0, 1.75, 1.36, 0.0][i]
var cases: Array = [
	["пол", Vector3(0, 0.05, 0), Vector3(0, 0, -1), 180],
	["лестница 17 см", Vector3(17, 0.05, -6), Vector3(0, 0, -1), 150],
	["лестница 25 см", Vector3(21, 0.05, -6), Vector3(0, 0, -1), 150],
	["пандус 25°", Vector3(7, 0.05, -17), Vector3(0, 0, 1), 200],
	["пандус 50°", Vector3(11, 0.05, -15), Vector3(0, 0, 1), 150],
	["вниз 17 см", Vector3(17, 1.40, -11.5), Vector3(0, 0, 1), 120],
	["бег 25 см", Vector3(21, 0.05, -6), Vector3(0, 0, -1), 100],
	["присед 17 см", Vector3(17, 0.05, -6), Vector3(0, 0, -1), 250],
	["ящик 0.5 м", Vector3(-12, 0.05, -7), Vector3(0, 0, -1), 120],
	["конец", Vector3(-1000, 0, 0), Vector3.ZERO, 0],
]
func _ready() -> void:
	var map: Node = (load("res://maps/test_range/test_range.tscn") as PackedScene).instantiate()
	add_child(map)
	player = (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	player.setup(1, "T", Transform3D.IDENTITY, 1)
	add_child(player)
	start_case()
func start_case() -> void:
	var c: Array = cases[case_idx]
	var t := Transform3D(Basis.looking_at(c[2] if c[2] != Vector3.ZERO else Vector3.FORWARD), c[1])
	player.teleport(t)
	var inp := Player.InputState.new()
	inp.move = Vector2(0, -1)
	inp.sprint_held = cases[case_idx][0].begins_with("бег")
	inp.wants_crouch = cases[case_idx][0].begins_with("присед")
	player.debug_input = inp
	frames = 0; max_y = 0.0; air_ticks = 0; stalls = 0
func _physics_process(_d: float) -> void:
	if case_idx >= cases.size() or cases[case_idx][3] == 0:
		get_tree().quit(); return
	frames += 1
	if frames > 5:
		max_y = maxf(max_y, player.global_position.y)
		if not player.is_on_floor() and player.velocity.y > -3.0: air_ticks += 1
		if Vector2(player.velocity.x, player.velocity.z).length() < 4.0 and player.global_position.y < 0.9 * top_of(case_idx): stalls += 1
	if frames >= cases[case_idx][3]:
		print("%-16s z=%.2f  макс. высота %.2f м, в воздухе (не падение): %d, тиков с потерей скорости: %d" % [cases[case_idx][0], player.global_position.z, max_y, air_ticks, stalls])
		case_idx += 1
		if case_idx < cases.size() and cases[case_idx][3] > 0: start_case()

