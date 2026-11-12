class_name Match
extends Node3D
## Сцена боя: карта + бойцы + интерфейс.
## Бойцов создаёт только хост через MultiplayerSpawner, клиенты получают их
## автоматически (включая тех, кто был в игре до их подключения).
## Бой: пули летят в BulletManager; попадания, убийства и респавн решает хост.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## Группа маркеров спавна на карте (Marker3D).
const SPAWN_POINT_GROUP: StringName = &"spawn_points"
## Ниже этой высоты свой боец возвращается на точку спавна.
const KILL_HEIGHT: float = -50.0
## Через сколько секунд после смерти боец возрождается.
const RESPAWN_DELAY: float = 5.0

## На всех машинах: строка для ленты убийств.
signal kill_announced(killer_id: int, killer_name: String, victim_id: int, victim_name: String, headshot: bool)

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var bullets: BulletManager = $Bullets

var _next_spawn_index: int = 0


func _ready() -> void:
	_spawner.spawn_function = _spawn_player
	bullets.soldier_hit.connect(_on_soldier_hit)
	Network.player_registered_on_host.connect(_on_player_registered_on_host)
	Network.player_left.connect(_on_player_left)

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
		local_player.teleport(_pick_spawn_transform())


func get_local_player() -> Player:
	return get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) as Player


# --- Спавн (решает хост) --------------------------------------------------

func _on_player_registered_on_host(peer_id: int) -> void:
	if _players.has_node(str(peer_id)):
		return
	var data: Array = [peer_id, Network.get_player_name(peer_id), _pick_spawn_transform()]
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
	var player := PLAYER_SCENE.instantiate() as Player
	player.setup(peer_id, player_name, spawn_transform)
	player.killed_on_host.connect(_on_player_killed)
	print("[match] боец «%s» (%d) создан" % [player_name, peer_id])
	return player


# --- Бой (решает хост) ----------------------------------------------------

func _on_soldier_hit(target: Player, shooter_id: int, damage: float, headshot: bool) -> void:
	if not Network.is_host() or not is_instance_valid(target):
		return
	var shooter := _players.get_node_or_null(str(shooter_id)) as Player
	var from: Vector3 = shooter.global_position if shooter != null else target.global_position
	target.server_apply_damage(damage, shooter_id, headshot, from)


func _on_player_killed(victim: Player, killer_id: int, headshot: bool) -> void:
	if not Network.is_host():
		return
	var killer := _players.get_node_or_null(str(killer_id)) as Player
	if killer != null and killer != victim:
		killer.kills += 1
	print("[match] %s убил %s%s" % [Network.get_player_name(killer_id), victim.display_name,
			" (в голову)" if headshot else ""])
	_announce_kill.rpc(killer_id, Network.get_player_name(killer_id), victim.peer_id,
			victim.display_name, headshot)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_instance_valid(victim) and not victim.alive and Network.is_host():
		victim.server_respawn(_pick_spawn_transform())


@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_id: int, killer_name: String, victim_id: int, victim_name: String,
		headshot: bool) -> void:
	kill_announced.emit(killer_id, killer_name, victim_id, victim_name, headshot)


## Следующая точка спавна по кругу; занятые (боец ближе 1.5 м) пропускаем.
func _pick_spawn_transform() -> Transform3D:
	var points: Array[Node] = get_tree().get_nodes_in_group(SPAWN_POINT_GROUP)
	if points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.UP)
	for attempt: int in points.size():
		var point := points[(_next_spawn_index + attempt) % points.size()] as Node3D
		if not _is_occupied(point.global_position):
			_next_spawn_index = (_next_spawn_index + attempt + 1) % points.size()
			return point.global_transform
	var fallback := points[_next_spawn_index % points.size()] as Node3D
	_next_spawn_index += 1
	return fallback.global_transform


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
