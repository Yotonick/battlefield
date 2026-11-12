class_name TdmRules
extends Node
## Правила командного боя (TDM): две команды, счёт по убийствам,
## лимит убийств и времени, экран итогов, новый раунд.
##
## Всё решает хост, остальные получают состояние целиком (_receive_state)
## при каждом изменении и раз в 2 секунды (для таймера).
##
## Решения владельца (чат 5): огня по своим нет; команду игрок выбирает сам.
##
## Фазы:
##   WAITING — в одной из команд никого нет; убийства в счёт не идут.
##   PLAYING — идёт раунд.
##   ENDED   — итоги: бойцы стоят, урона нет; через results_time — новый раунд.

enum Phase { WAITING, PLAYING, ENDED }

const TEAM_NONE: int = 0
const TEAM_BLUE: int = 1
const TEAM_RED: int = 2
const TEAM_NAMES: Array[String] = ["Без команды", "Синие", "Красные"]
const TEAM_COLORS: Array[Color] = [Color(0.8, 0.8, 0.8), Color(0.45, 0.68, 1.0), Color(1.0, 0.45, 0.38)]
const GROUP: StringName = &"match_rules"
## Как часто хост рассылает состояние без изменений (для таймера), секунд.
const RESYNC_INTERVAL: float = 2.0

## На всех машинах: состояние обновилось (команды, счёт, фаза).
signal state_changed
## На всех машинах: сменилась фаза (для баннеров и звуков).
signal phase_changed(new_phase: Phase, old_phase: Phase)

var phase: Phase = Phase.WAITING
## peer id → команда. Здесь все зарегистрированные игроки, в том числе
## те, кто ещё не выбрал команду (TEAM_NONE).
var teams: Dictionary[int, int] = {}
## Счёт команд: индекс = номер команды (0 не используется).
var scores: Array[int] = [0, 0, 0]
var kill_limit: int = MatchSettings.DEFAULT_KILL_LIMIT
var time_limit: int = MatchSettings.DEFAULT_TIME_LIMIT
## Осталось секунд: в PLAYING — до конца раунда, в ENDED — до нового.
var time_left: float = 0.0
## Победитель последнего раунда (0 — ничья).
var winner: int = TEAM_NONE
## Номер раунда — чтобы HUD отличал «новый раунд» от повтора состояния.
var round_number: int = 0

var _match: Match
var _resync_timer: float = 0.0
var _auto_team_sent: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_match = get_parent() as Match
	Network.player_registered_on_host.connect(_on_player_registered_on_host)
	Network.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	if phase != Phase.WAITING:
		time_left = maxf(time_left - delta, 0.0)
	_update_local_freeze()
	if not Network.is_host():
		return
	match phase:
		Phase.PLAYING:
			if time_left <= 0.0:
				_end_round(_leader())
		Phase.ENDED:
			if time_left <= 0.0:
				if _both_teams_present():
					_start_round()
				else:
					_set_phase(Phase.WAITING)
					_broadcast()
	_resync_timer += delta
	if _resync_timer >= RESYNC_INTERVAL:
		_broadcast()


# --- Для всех машин -------------------------------------------------------

static func get_rules(tree: SceneTree) -> TdmRules:
	return tree.get_first_node_in_group(GROUP) as TdmRules


func get_team(peer_id: int) -> int:
	return teams.get(peer_id, TEAM_NONE)


func get_local_team() -> int:
	return get_team(multiplayer.get_unique_id())


func count_team(team: int) -> int:
	var count: int = 0
	for peer_id: int in teams:
		if teams[peer_id] == team:
			count += 1
	return count


## Можно ли сейчас наносить урон (на итогах раунда — нет).
func allows_damage() -> bool:
	return phase != Phase.ENDED


## Свой боец на итогах стоит и не стреляет.
func _update_local_freeze() -> void:
	var me: Player = _match.get_local_player() if _match != null else null
	if me != null:
		me.frozen = phase == Phase.ENDED


## Попросить хоста сменить команду (0 — в ту, где меньше игроков).
func request_team(team: int) -> void:
	_server_request_team.rpc_id(1, team)


# --- Хост -----------------------------------------------------------------

func _on_player_registered_on_host(peer_id: int) -> void:
	if not teams.has(peer_id):
		teams[peer_id] = TEAM_NONE
	kill_limit = Network.match_settings.kill_limit
	time_limit = Network.match_settings.time_limit
	_broadcast()


func _on_player_left(peer_id: int, _player_name: String) -> void:
	if not Network.is_host():
		return
	teams.erase(peer_id)
	_check_round_can_continue()
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func _server_request_team(team: int) -> void:
	if not Network.is_host():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not teams.has(peer_id):
		return  # не прошёл регистрацию
	var current: int = teams[peer_id]
	if team != TEAM_BLUE and team != TEAM_RED:
		team = _smaller_team(current)
	var soldier: Player = _match.get_soldier(peer_id)
	if team == current and soldier != null:
		return
	teams[peer_id] = team
	print("[tdm] %s → %s" % [Network.get_player_name(peer_id), TEAM_NAMES[team]])
	if soldier == null:
		_match.spawn_soldier(peer_id, team)
	else:
		# Смена команды без штрафа: просто переносим на базу новой команды.
		soldier.team = team
		soldier.server_respawn(_match.pick_spawn_transform(team))
	if phase == Phase.WAITING and _both_teams_present():
		_start_round()
	else:
		_check_round_can_continue()
	_broadcast()


## Хост: боец убит (вызывает Match). Возвращает true, если убийство пошло в счёт.
func server_on_kill(killer_id: int, victim: Player) -> bool:
	if not Network.is_host() or phase != Phase.PLAYING:
		return false
	var killer_team: int = get_team(killer_id)
	if killer_team == TEAM_NONE or killer_team == victim.team or killer_id == victim.peer_id:
		return false
	scores[killer_team] += 1
	if scores[killer_team] >= kill_limit:
		_end_round(killer_team)
	_broadcast()
	return true


## В какую команду отправить «авто»: где меньше игроков, при равенстве — где меньше очков.
func _smaller_team(exclude_peer_team: int) -> int:
	var blue: int = count_team(TEAM_BLUE) - (1 if exclude_peer_team == TEAM_BLUE else 0)
	var red: int = count_team(TEAM_RED) - (1 if exclude_peer_team == TEAM_RED else 0)
	if blue != red:
		return TEAM_BLUE if blue < red else TEAM_RED
	if scores[TEAM_BLUE] != scores[TEAM_RED]:
		return TEAM_BLUE if scores[TEAM_BLUE] < scores[TEAM_RED] else TEAM_RED
	return TEAM_BLUE if randi() % 2 == 0 else TEAM_RED


func _both_teams_present() -> bool:
	return count_team(TEAM_BLUE) > 0 and count_team(TEAM_RED) > 0


## Если посреди раунда одна команда опустела — раунд прерывается.
func _check_round_can_continue() -> void:
	if phase == Phase.PLAYING and not _both_teams_present():
		print("[tdm] раунд прерван: одна из команд пуста")
		_set_phase(Phase.WAITING)


func _leader() -> int:
	if scores[TEAM_BLUE] == scores[TEAM_RED]:
		return TEAM_NONE
	return TEAM_BLUE if scores[TEAM_BLUE] > scores[TEAM_RED] else TEAM_RED


func _start_round() -> void:
	kill_limit = Network.match_settings.kill_limit
	time_limit = Network.match_settings.time_limit
	scores = [0, 0, 0]
	winner = TEAM_NONE
	round_number += 1
	time_left = float(time_limit)
	_set_phase(Phase.PLAYING)
	print("[tdm] раунд %d начался: до %d убийств, %d с" % [round_number, kill_limit, time_limit])
	# Все на свои базы, счёт бойцов с нуля.
	for soldier: Player in _match.get_soldiers():
		soldier.kills = 0
		soldier.deaths = 0
		var team: int = get_team(soldier.peer_id)
		if team != TEAM_NONE:
			soldier.server_respawn(_match.pick_spawn_transform(team))
	_broadcast()


func _end_round(winning_team: int) -> void:
	winner = winning_team
	time_left = Network.match_settings.results_time
	_set_phase(Phase.ENDED)
	print("[tdm] раунд %d окончен: %s, счёт %d:%d" % [round_number,
			"ничья" if winning_team == TEAM_NONE else "победа: " + TEAM_NAMES[winning_team],
			scores[TEAM_BLUE], scores[TEAM_RED]])
	_broadcast()


func _set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	var old: Phase = phase
	phase = new_phase
	phase_changed.emit(new_phase, old)


func _broadcast() -> void:
	_resync_timer = 0.0
	state_changed.emit()
	_maybe_auto_pick_team()
	if multiplayer.multiplayer_peer == null or not Network.is_host():
		return
	var plain_teams: Dictionary = {}
	for peer_id: int in teams:
		plain_teams[peer_id] = teams[peer_id]
	_receive_state.rpc({
		"phase": phase,
		"teams": plain_teams,
		"scores": scores,
		"kill_limit": kill_limit,
		"time_limit": time_limit,
		"time_left": time_left,
		"winner": winner,
		"round": round_number,
	})


# --- Клиент ---------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _receive_state(state: Dictionary) -> void:
	teams.clear()
	var raw_teams: Dictionary = state.get("teams", {})
	for key: Variant in raw_teams:
		teams[int(key)] = int(raw_teams[key])
	var raw_scores: Array = state.get("scores", [0, 0, 0])
	scores = [int(raw_scores[0]), int(raw_scores[1]), int(raw_scores[2])]
	kill_limit = int(state.get("kill_limit", kill_limit))
	time_limit = int(state.get("time_limit", time_limit))
	time_left = float(state.get("time_left", 0.0))
	winner = int(state.get("winner", TEAM_NONE))
	round_number = int(state.get("round", 0))
	_set_phase(int(state.get("phase", Phase.WAITING)) as Phase)
	state_changed.emit()
	_maybe_auto_pick_team()


## Запуск с --team=…: выбрать команду сразу, без экрана.
func _maybe_auto_pick_team() -> void:
	if _auto_team_sent or Network.requested_team < 0:
		return
	if not teams.has(multiplayer.get_unique_id()):
		return
	_auto_team_sent = true
	request_team(Network.requested_team)
