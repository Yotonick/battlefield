class_name Match
extends Node3D
## Сцена боя: карта + бойцы + правила (TDM) + интерфейс.
## Бойцов создаёт только хост через MultiplayerSpawner, клиенты получают их
## автоматически (включая тех, кто был в игре до их подключения).
## Боец появляется, когда игрок выбрал команду (см. TdmRules).
## Бой: пули летят в BulletManager; попадания, убийства и респавн решает хост.
##
## Карта: хост загружает её сразу (выбрана в меню), клиент — когда хост
## прислал настройки матча (Network.match_settings_received).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## Общие точки спавна (Marker3D) — если у карты нет точек команд.
const SPAWN_POINT_GROUP: StringName = &"spawn_points"
## Точки спавна команды N: группа "spawn_team_N".
const TEAM_SPAWN_GROUP_PREFIX: String = "spawn_team_"
## Точку, на которую только что кого-то поставили, какое-то время не занимаем.
const SPAWN_RESERVE_MS: int = 2500
## Ниже этой высоты свой боец возвращается на точку спавна.
const KILL_HEIGHT: float = -50.0
## Через сколько секунд после смерти боец возрождается.
const RESPAWN_DELAY: float = 5.0

## На всех машинах: строка для ленты убийств.
signal kill_announced(killer_id: int, killer_name: String, killer_team: int,
		victim_id: int, victim_name: String, victim_team: int, headshot: bool)
## Карта загружена (у клиента — после настроек от хоста).
signal map_loaded

@onready var _map_root: Node3D = $Map
@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var bullets: BulletManager = $Bullets
@onready var rules: TdmRules = $Rules

var map_id: String = ""
## Marker3D → время (мс), до которого точка считается занятой.
var _reserved_spawns: Dictionary[Node3D, int] = {}
var _overview_camera: Camera3D = null


func _ready() -> void:
	_spawner.spawn_function = _spawn_player
	bullets.soldier_hit.connect(_on_soldier_hit)
	Network.player_left.connect(_on_player_left)
	Network.match_settings_received.connect(_on_match_settings_received)

	# Хост знает карту сразу; клиент узнает её от хоста после подключения.
	if Network.is_pending_host():
		_load_map(Network.match_settings.map_id)
	var error: String = Network.start_pending()
	if not error.is_empty():
		Network.leave(error)
		return
	_update_window_title()
	Network.player_list_changed.connect(_update_window_title)
	_maybe_start_autotest()


## Автотест боя: только при запуске с --test=… (см. tests/combat_test.gd).
func _maybe_start_autotest() -> void:
	var args := PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--test="):
			var script := load("res://tests/combat_test.gd") as GDScript
			var driver: Node = script.new() as Node
			driver.set(&"mode", arg.trim_prefix("--test="))
			add_child(driver)
			return


func _physics_process(_delta: float) -> void:
	var local_player := get_local_player()
	if local_player != null and local_player.global_position.y < KILL_HEIGHT:
		local_player.teleport(pick_spawn_transform(local_player.team))


## Пока у игрока нет бойца (выбирает команду) — вид на карту сверху.
func _process(_delta: float) -> void:
	var has_local: bool = get_local_player() != null
	if not has_local and has_map() and _overview_camera == null:
		_overview_camera = Camera3D.new()
		_overview_camera.name = "OverviewCamera"
		_overview_camera.fov = 70.0
		_overview_camera.far = 1000.0
		add_child(_overview_camera)
		_overview_camera.look_at_from_position(Vector3(-25, 70, 85), Vector3.ZERO, Vector3.UP)
		_overview_camera.current = true
	elif has_local and _overview_camera != null:
		_overview_camera.queue_free()
		_overview_camera = null


func get_local_player() -> Player:
	return get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) as Player


func get_soldier(peer_id: int) -> Player:
	return _players.get_node_or_null(str(peer_id)) as Player


func get_soldiers() -> Array[Player]:
	var result: Array[Player] = []
	for child: Node in _players.get_children():
		var soldier := child as Player
		if soldier != null and not soldier.is_queued_for_deletion():
			result.append(soldier)
	return result


func has_map() -> bool:
	return _map_root.get_child_count() > 0


# --- Карта ----------------------------------------------------------------

func _on_match_settings_received() -> void:
	if not has_map():
		_load_map(Network.match_settings.map_id)


func _load_map(id: String) -> void:
	map_id = id if MatchSettings.MAPS.has(id) else MatchSettings.DEFAULT_MAP
	var scene := load(MatchSettings.MAPS[map_id]) as PackedScene
	if scene == null:
		Network.leave("Не удалось загрузить карту «%s»" % map_id)
		return
	_map_root.add_child(scene.instantiate())
	print("[match] карта: %s" % MatchSettings.MAP_TITLES.get(map_id, map_id))
	map_loaded.emit()


# --- Спавн (решает хост) --------------------------------------------------

## Хост: создать бойца игроку, выбравшему команду.
func spawn_soldier(peer_id: int, team: int) -> void:
	if _players.has_node(str(peer_id)):
		return
	var data: Array = [peer_id, Network.get_player_name(peer_id), pick_spawn_transform(team), team]
	_spawner.spawn(data)


func _on_player_left(peer_id: int, _player_name: String) -> void:
	if not Network.is_host():
		return
	var node: Node = _players.get_node_or_null(str(peer_id))
	if node != null:
		node.queue_free()


## Выполняется на каждой машине с одинаковыми данными.
func _spawn_player(data: Variant) -> Node:
	var args: Array = data as Array
	var peer_id: int = int(args[0])
	var player_name: String = str(args[1])
	var spawn_transform: Transform3D = args[2] as Transform3D
	var team: int = int(args[3])
	var player := PLAYER_SCENE.instantiate() as Player
	player.setup(peer_id, player_name, spawn_transform, team)
	player.killed_on_host.connect(_on_player_killed)
	print("[match] боец «%s» (%d) создан" % [player_name, peer_id])
	return player


# --- Бой (решает хост) ----------------------------------------------------

func _on_soldier_hit(target: Player, shooter_id: int, damage: float, headshot: bool) -> void:
	if not Network.is_host() or not is_instance_valid(target) or not rules.allows_damage():
		return
	var shooter := _players.get_node_or_null(str(shooter_id)) as Player
	# Огня по своим нет (решение владельца). Пули и так пролетают сквозь своих,
	# это страховка на случай смены команды, пока пуля в полёте.
	if shooter != null and shooter.team == target.team and shooter != target:
		return
	var from: Vector3 = shooter.global_position if shooter != null else target.global_position
	target.server_apply_damage(damage, shooter_id, headshot, from)


func _on_player_killed(victim: Player, killer_id: int, headshot: bool) -> void:
	if not Network.is_host():
		return
	var killer := _players.get_node_or_null(str(killer_id)) as Player
	if killer != null and killer != victim:
		killer.kills += 1
	rules.server_on_kill(killer_id, victim)
	print("[match] %s убил %s%s" % [Network.get_player_name(killer_id), victim.display_name,
			" (в голову)" if headshot else ""])
	var killer_team: int = killer.team if killer != null else rules.get_team(killer_id)
	_announce_kill.rpc(killer_id, Network.get_player_name(killer_id), killer_team, victim.peer_id,
			victim.display_name, victim.team, headshot)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_instance_valid(victim) and not victim.alive and Network.is_host():
		victim.server_respawn(pick_spawn_transform(victim.team))


@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_id: int, killer_name: String, killer_team: int, victim_id: int,
		victim_name: String, victim_team: int, headshot: bool) -> void:
	kill_announced.emit(killer_id, killer_name, killer_team, victim_id, victim_name, victim_team, headshot)


## Точка спавна команды: свободная и подальше от живых врагов.
## Если у карты нет точек команд — общие точки spawn_points.
func pick_spawn_transform(team: int) -> Transform3D:
	var points: Array[Node] = get_tree().get_nodes_in_group(StringName(TEAM_SPAWN_GROUP_PREFIX + str(team)))
	if points.is_empty():
		points = get_tree().get_nodes_in_group(SPAWN_POINT_GROUP)
	if points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP)
	var now: int = Time.get_ticks_msec()
	var best: Node3D = null
	var best_score: float = -INF
	for node: Node in points:
		var point := node as Node3D
		if point == null:
			continue
		var score: float = _distance_to_nearest_enemy(point.global_position, team)
		score += randf() * 2.0  # чтобы не всегда одна и та же точка
		if _is_occupied(point.global_position) or _reserved_spawns.get(point, 0) > now:
			score -= 10000.0
		if score > best_score:
			best_score = score
			best = point
	_reserved_spawns[best] = now + SPAWN_RESERVE_MS
	return best.global_transform


func _distance_to_nearest_enemy(position_to_check: Vector3, team: int) -> float:
	var nearest: float = 1000.0
	for soldier: Player in get_soldiers():
		if soldier.alive and soldier.team != team:
			nearest = minf(nearest, soldier.global_position.distance_to(position_to_check))
	return nearest


func _is_occupied(position_to_check: Vector3) -> bool:
	for child: Node in _players.get_children():
		var other := child as Node3D
		var soldier := other as Player
		if soldier != null and not soldier.alive:
			continue
		if other != null and other.global_position.distance_to(position_to_check) < 1.5:
			return true
	return false


func _update_window_title() -> void:
	var role: String = "хост" if Network.is_host() else "клиент"
	get_window().title = "Battlefield — %s — %s (%d в игре)" % [
		role, Network.get_player_name(multiplayer.get_unique_id()), Network.players.size()]
