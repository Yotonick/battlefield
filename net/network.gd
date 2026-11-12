extends Node
## Сеть: создание игры (хост = сервер) и подключение по IP.
## Автозагрузка с именем `Network` (Project Settings → Globals).
##
## Порядок запуска:
## 1. Меню записывает намерение (`request_host` / `request_join`) и
##    переключает сцену на матч.
## 2. Сцена матча в `_ready` вызывает `start_pending()` — сеть поднимается,
##    когда MultiplayerSpawner уже в дереве. Так клиент никогда не получает
##    пакеты о бойцах раньше, чем у него загрузилась карта.
## 3. Клиент после подключения отправляет хосту имя и версию игры.
##    Хост проверяет версию, добавляет игрока в список и рассылает список всем.

signal player_list_changed
## Игрок прошёл регистрацию (вызывается на всех машинах).
signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int, player_name: String)
## Только на хосте: пора создать бойца для игрока.
signal player_registered_on_host(peer_id: int)
## Сеть остановлена: ошибка, хост ушёл, кик или выход по желанию.
## Пустая причина = вышли сами.
signal session_ended(reason: String)

enum Mode { NONE, HOST, CLIENT }

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 6
const MAX_NAME_LENGTH: int = 16
## Сколько ждать ответа хоста при подключении, мс.
const CONNECT_TIMEOUT_MS: int = 6000
## Через сколько мс без ответа считать игрока/хоста отвалившимся
## (вылет игры, пропал интернет). По умолчанию у ENet до 30 с.
const DROP_TIMEOUT_MS: int = 8000
const MENU_SCENE: String = "res://ui/main_menu/main_menu.tscn"
const MATCH_SCENE: String = "res://match/match.tscn"
const SETTINGS_PATH: String = "user://settings.cfg"

var mode: Mode = Mode.NONE
## peer_id → имя. На хосте — источник правды, у клиентов — копия.
var players: Dictionary[int, String] = {}

var player_name: String = ""
var last_join_address: String = "127.0.0.1"
var port: int = DEFAULT_PORT
## Сообщение для меню после возврата (почему вылетели).
var last_end_reason: String = ""

var _pending_mode: Mode = Mode.NONE
var _pending_address: String = ""
var _ending: bool = false


func _ready() -> void:
	_load_settings()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_apply_command_line.call_deferred()


# --- Запуск из меню -------------------------------------------------------

func request_host() -> void:
	_pending_mode = Mode.HOST
	save_settings()
	get_tree().change_scene_to_file(MATCH_SCENE)


func request_join(address: String) -> void:
	_pending_mode = Mode.CLIENT
	_pending_address = address.strip_edges()
	last_join_address = _pending_address
	save_settings()
	get_tree().change_scene_to_file(MATCH_SCENE)


## Вызывается сценой матча. Возвращает пустую строку или текст ошибки.
func start_pending() -> String:
	var pending: Mode = _pending_mode
	_pending_mode = Mode.NONE
	match pending:
		Mode.HOST:
			return _start_host()
		Mode.CLIENT:
			return _start_client(_pending_address)
	return "Не выбран режим: создать игру или подключиться"


## Выйти в главное меню (по кнопке или после ошибки).
## Сама остановка сети откладывается до конца кадра: её нельзя делать
## прямо внутри обработки сетевого пакета или сигнала.
func leave(reason: String = "") -> void:
	if _ending:
		return
	_ending = true
	last_end_reason = reason
	_finish_leave.call_deferred(reason)


func _finish_leave(reason: String) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players.clear()
	print("[net] сессия завершена: %s" % (reason if not reason.is_empty() else "выход"))
	session_ended.emit(reason)
	get_tree().change_scene_to_file(MENU_SCENE)
	_ending = false


func is_host() -> bool:
	return mode == Mode.HOST


func is_online() -> bool:
	return mode != Mode.NONE


func get_player_name(peer_id: int) -> String:
	return players.get(peer_id, "Игрок %d" % peer_id)


## Пинг до хоста в мс (на хосте — 0, без связи — -1).
func get_ping_ms() -> int:
	if mode == Mode.HOST:
		return 0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return -1
	var host_peer: ENetPacketPeer = enet.get_peer(1)
	if host_peer == null:
		return -1
	return int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## IPv4-адреса этого компьютера. Адреса Radmin VPN (26.x.x.x) идут первыми.
func get_local_ipv4_addresses() -> PackedStringArray:
	var radmin := PackedStringArray()
	var other := PackedStringArray()
	for address: String in IP.get_local_addresses():
		if address.count(".") != 3 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.begins_with("26."):
			radmin.append(address)
		else:
			other.append(address)
	radmin.append_array(other)
	return radmin


# --- Хост и клиент --------------------------------------------------------

func _start_host() -> String:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return "Не удалось создать игру на порту %d (%s). Порт занят другой программой?" % [
			port, error_string(error)]
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	players.clear()
	players[1] = _sanitize_name(player_name, 1)
	print("[net] хост запущен, порт %d, игрок «%s»" % [port, players[1]])
	player_list_changed.emit()
	player_joined.emit(1, players[1])
	player_registered_on_host.emit(1)
	return ""


func _start_client(address: String) -> String:
	if address.is_empty():
		return "Не указан IP-адрес хоста"
	var host_address: String = address
	var host_port: int = port
	# Можно ввести «26.1.2.3:7777».
	if address.count(":") == 1:
		host_address = address.get_slice(":", 0)
		host_port = address.get_slice(":", 1).to_int()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(host_address, host_port)
	if error != OK:
		return "Не удалось начать подключение к %s (%s)" % [address, error_string(error)]
	# Быстрый отказ, если хост не отвечает (по умолчанию ENet ждёт ~30 с).
	peer.get_peer(1).set_timeout(0, CONNECT_TIMEOUT_MS, CONNECT_TIMEOUT_MS)
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players.clear()
	print("[net] подключение к %s:%d…" % [host_address, host_port])
	return ""


func _on_connected_to_server() -> void:
	# После подключения — таймаут обрыва связи.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.get_peer(1) != null:
		enet.get_peer(1).set_timeout(0, 3000, DROP_TIMEOUT_MS)
	print("[net] подключились к хосту, мой id %d" % multiplayer.get_unique_id())
	_register_on_host.rpc_id(1, player_name, _game_version())


func _on_connection_failed() -> void:
	leave("Не удалось подключиться. Проверьте IP, что хост создал игру и что Radmin VPN включён. Ещё вариант: в игре уже %d игроков." % MAX_PLAYERS)


func _on_server_disconnected() -> void:
	leave("Связь с хостом потеряна (хост вышел из игры или пропала сеть).")


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.get_peer(peer_id) != null:
			enet.get_peer(peer_id).set_timeout(0, 3000, DROP_TIMEOUT_MS)
		print("[net] подключился peer %d, ждём регистрацию" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host() or not players.has(peer_id):
		return
	var left_name: String = players[peer_id]
	players.erase(peer_id)
	print("[net] вышел «%s» (%d)" % [left_name, peer_id])
	_broadcast_player_list()
	_announce_left.rpc(peer_id, left_name)
	player_left.emit(peer_id, left_name)


# --- RPC ------------------------------------------------------------------

## Клиент → хост: «я такой-то, версия такая-то».
@rpc("any_peer", "reliable")
func _register_on_host(requested_name: String, version: String) -> void:
	if not is_host():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if players.has(peer_id):
		return
	if version != _game_version():
		_kick(peer_id, "Разные версии игры: у хоста %s, у вас %s. Скачайте свежую версию из GitHub." % [
			_game_version(), version])
		return
	var final_name: String = _sanitize_name(requested_name, peer_id)
	players[peer_id] = final_name
	print("[net] зарегистрирован «%s» (%d)" % [final_name, peer_id])
	_broadcast_player_list()
	_announce_joined.rpc(peer_id, final_name)
	player_joined.emit(peer_id, final_name)
	player_registered_on_host.emit(peer_id)


@rpc("authority", "reliable")
func _receive_player_list(list: Dictionary) -> void:
	players.clear()
	for key: Variant in list:
		players[int(key)] = str(list[key])
	player_list_changed.emit()


@rpc("authority", "reliable")
func _announce_joined(peer_id: int, joined_name: String) -> void:
	player_joined.emit(peer_id, joined_name)


@rpc("authority", "reliable")
func _announce_left(peer_id: int, left_name: String) -> void:
	player_left.emit(peer_id, left_name)


@rpc("authority", "reliable")
func _kicked(reason: String) -> void:
	leave(reason)


func _kick(peer_id: int, reason: String) -> void:
	print("[net] отключаем %d: %s" % [peer_id, reason])
	_kicked.rpc_id(peer_id, reason)
	# Даём сообщению уйти, потом рвём связь.
	await get_tree().create_timer(0.5).timeout
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	# Клиент мог уже отключиться сам, получив сообщение.
	if enet != null and is_host() and multiplayer.get_peers().has(peer_id):
		enet.disconnect_peer(peer_id)


func _broadcast_player_list() -> void:
	player_list_changed.emit()
	var plain: Dictionary = {}
	for peer_id: int in players:
		plain[peer_id] = players[peer_id]
	_receive_player_list.rpc(plain)


# --- Вспомогательное ------------------------------------------------------

func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


## Обрезает имя, убирает пустое и повторы («Вася» → «Вася (2)»).
func _sanitize_name(raw: String, peer_id: int) -> String:
	var clean: String = raw.strip_edges().replace("\n", " ").left(MAX_NAME_LENGTH)
	if clean.is_empty():
		clean = "Игрок %d" % peer_id
	var taken: Array = players.values()
	var result: String = clean
	var index: int = 2
	while taken.has(result):
		result = "%s (%d)" % [clean, index]
		index += 1
	return result


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		player_name = str(config.get_value("player", "name", ""))
		last_join_address = str(config.get_value("network", "last_address", last_join_address))
		port = int(config.get_value("network", "port", DEFAULT_PORT))
	if player_name.is_empty():
		player_name = OS.get_environment("USERNAME").left(MAX_NAME_LENGTH)
	if player_name.is_empty():
		player_name = "Боец"


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("network", "last_address", last_join_address)
	config.set_value("network", "port", port)
	config.save(SETTINGS_PATH)


## Быстрый запуск для тестов, без меню:
##   --host               создать игру
##   --join=127.0.0.1     подключиться
##   --name=Вася          имя (не сохраняется в настройки)
##   --port=7777
func _apply_command_line() -> void:
	var args := PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	var want_host: bool = false
	var join_address: String = ""
	for arg: String in args:
		if arg == "--host":
			want_host = true
		elif arg.begins_with("--join="):
			join_address = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=").left(MAX_NAME_LENGTH)
		elif arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	if want_host:
		_pending_mode = Mode.HOST
		get_tree().change_scene_to_file(MATCH_SCENE)
	elif not join_address.is_empty():
		_pending_mode = Mode.CLIENT
		_pending_address = join_address
		get_tree().change_scene_to_file(MATCH_SCENE)
