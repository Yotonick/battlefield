extends Node
## Автотест боя (запускается только с аргументом --test=…, в игре не участвует).
##
##   --test=ballistics   один хост: выстрел без разброса в столб на 100 м,
##                       печатает точку попадания и падение пули.
##   --test=shooter      стреляет в другого бойца (роль хоста или клиента — любая)
##   --test=target       мишень: стоит, бегает влево-вправо, потом встаёт вплотную
##   --test=observer     подключиться позже и напечатать здоровье/счёт всех бойцов
##
## TDM (шаг 4), все с --map=test_range:
##   --test=tdm_shooter  хост, --team=1: стреляет в союзника (урона быть не должно),
##                       потом во врага до конца раунда; ждёт новый раунд
##   --test=tdm_mate     --team=1: союзник-мишень
##   --test=tdm_enemy    --team=2: враг-мишень
##   --test=tdm_idle     раунд по времени (--round-time=6): ждём ничью
##
## Карта (шаг 4):
## Оружие (v0.2):
##   --test=guns         хост, --team=1, --map=test_range: каждый ствол каталога
##                       от бедра и в прицеле, смена оружия, меню снаряжения;
##                       скриншоты с --screens=папка
##
##   --test=town         хост, --map=town: точки спавна, подъём по пандусам,
##                       скриншоты с --screens=папка
##
## Стрелок и мишень (shooter/target) — в разных командах: --team=1 и --team=2.
##
## Фазы мишени по числу её смертей: 0 — стоит (в тело), 1 — бегает (в тело),
## 2 — стоит (в голову), 3 — подходит вплотную к стрелку (проверка расталкивания).

const TARGET_SPOT := Vector3(0.0, 0.05, -12.0)
const SHOOTER_SPOT := Vector3(0.0, 0.05, 8.0)
const MATE_SPOT := Vector3(-3.0, 0.05, -12.0)
const ENEMY_SPOT := Vector3(3.0, 0.05, -12.0)
const TIMEOUT: float = 75.0
const FLOOR_HEIGHT_TEST: float = 3.3

var mode: String = ""
var _match: Match
var _me: Player
var _other: Player
var _time: float = 0.0
var _phase_time: float = 0.0
var _last_phase: int = -1
var _shots: int = 0
var _hits: int = 0
var _hits_per_phase: Dictionary[int, Vector2i] = {}
var _done: bool = false
var _input := Player.InputState.new()
var _strafe_dir: float = 1.0
var _push_start_ms: int = 0
## --screens=папка: сохранять скриншоты ключевых моментов.
var _screens_dir: String = ""
var _snapped: Dictionary[String, bool] = {}
var _prev_fire_held: bool = false


func _ready() -> void:
	_match = get_parent() as Match
	print("[test] режим %s, снаряжение: %s" % [mode, ", ".join(
			WeaponCatalog.get_loadout().map(func(w: WeaponData) -> String: return w.display_name))])
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--screens="):
			_screens_dir = arg.trim_prefix("--screens=")
	if mode == "ballistics":
		_match.bullets.world_impact.connect(_on_impact)


func _physics_process(delta: float) -> void:
	_time += delta
	if _done:
		return
	if _time > TIMEOUT:
		_finish("таймаут")
		return
	if mode == "ui":
		_ui_tick()
		return
	if mode == "feel":
		_feel_physics()
		return
	if mode == "guns" and _me != null:
		_guns_tick(delta)
		_input.fire_pressed = _input.fire_held and not _prev_fire_held
		_prev_fire_held = _input.fire_held
		return
	if _me == null:
		_me = _match.get_local_player()
		if _me == null:
			return
		_me.debug_input = _input
		_me.hit_confirmed.connect(_on_hit_confirmed)
		_me.weapon.shot_fired.connect(func() -> void: _shots += 1)
	match mode:
		"ballistics":
			_ballistics_tick()
		"shooter":
			_shooter_tick(delta)
		"target":
			_target_tick(delta)
		"tdm_shooter":
			_tdm_shooter_tick(delta)
		"tdm_mate":
			_tdm_target_tick(MATE_SPOT)
		"tdm_enemy":
			_tdm_target_tick(ENEMY_SPOT)
		"tdm_idle":
			_tdm_idle_tick()
		"town":
			_town_tick(delta)
		"observer":
			if _time > 3.0:
				for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
					var soldier := node as Player
					print("[test] наблюдатель: %s — здоровье %.0f, жив %s, убийств %d, смертей %d" % [
						soldier.display_name, soldier.health, soldier.alive, soldier.kills, soldier.deaths])
				_finish("наблюдатель")
	# Одиночный огонь и очередь срабатывают по нажатию, а не по удержанию.
	_input.fire_pressed = _input.fire_held and not _prev_fire_held
	_prev_fire_held = _input.fire_held


func _find_other() -> Player:
	for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
		var soldier := node as Player
		if soldier != null and soldier != _me:
			return soldier
	return null


# --- Баллистика -----------------------------------------------------------

var _ballistics_fired: bool = false
var _shot_origin: Vector3 = Vector3.ZERO


func _ballistics_tick() -> void:
	if _time < 1.0:
		return
	if not _ballistics_fired:
		var precise: WeaponData = _me.weapon.weapon.duplicate() as WeaponData
		precise.spread_hip = 0.0
		precise.spread_ads = 0.0
		precise.spread_move_multiplier = 1.0
		_me.weapon.weapon = precise
		# Столбы стоят в линию на 10/25/50/100 м — стреляем из-за 50-метрового в 100-метровый.
		_me.teleport(Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.05, -52.0)))
		_me.set_look(0.0, 0.0)
		_ballistics_fired = true
		_input.fire_held = false
		return
	if _time > 1.5 and _shots == 0:
		_shot_origin = _me.get_eye_position()
		_input.fire_held = true
	elif _shots > 0:
		_input.fire_held = false


func _on_impact(position: Vector3, _normal: Vector3) -> void:
	if mode != "ballistics" or _done:
		return
	var eye_y: float = _shot_origin.y
	var distance: float = absf(position.z - _shot_origin.z)
	var flight: float = distance / _me.weapon.weapon.muzzle_velocity
	var expected: float = 0.5 * 9.8 * flight * flight
	print("[test] попадание в %s, дистанция %.1f м, падение %.3f м (ожидалось %.3f), активных пуль %d" % [
		str(position.snapped(Vector3.ONE * 0.001)), distance, eye_y - position.y, expected,
		_match.bullets.get_active_count()])
	_finish("баллистика")


# --- Стрелок --------------------------------------------------------------

func _shooter_tick(delta: float) -> void:
	if _other == null:
		_other = _find_other()
		_input.fire_held = false
		return
	if not is_instance_valid(_other):
		_finish("мишень вышла")
		return
	if _me.global_position.distance_to(SHOOTER_SPOT) > 1.0 and _me.alive and _last_phase < 3:
		_me.teleport(Transform3D(Basis.IDENTITY, SHOOTER_SPOT))

	var phase: int = _other.deaths
	if phase != _last_phase:
		_last_phase = phase
		_phase_time = 0.0
		print("[test] фаза %d (мишень умерла %d раз), выстрелов %d, попаданий %d" % [
			phase, _other.deaths, _shots, _hits])
	_phase_time += delta
	if phase >= 3:
		_input.fire_held = false
		_input.aim_held = false
		if _phase_time > 1.5 and _phase_time < 4.0:
			# От бедра, по стене дома — трассеры, следы, прицел.
			_me.set_look(0.49, 0.06)
			_input.fire_held = fmod(_phase_time, 0.6) < 0.3
			if _phase_time > 2.2:
				_snap("hip")
		if _phase_time > 4.5 and _phase_time < 5.0:
			_input.reload_pressed = true
		if _phase_time > 5.2:
			_input.reload_pressed = false
			_snap("reload")
		if _push_start_ms == 0 and _phase_time > 7.0:
			_push_start_ms = Time.get_ticks_msec()
		if _push_start_ms > 0 and Time.get_ticks_msec() - _push_start_ms > 2500:
			var gap: float = Vector2(_me.global_position.x - _other.global_position.x,
					_me.global_position.z - _other.global_position.z).length()
			print("[test] расталкивание: расстояние между бойцами %.2f м" % gap)
			_finish("стрелок")
		return

	# Ждём, пока мишень встанет на место и оживёт.
	if not _other.alive or _other.global_position.distance_to(TARGET_SPOT) > 4.0 or _phase_time < 1.0:
		_input.fire_held = false
		_input.aim_held = true
		return
	var aim_height: float = 1.62 if phase == 2 else 1.0
	var target: Vector3 = _other.global_position + Vector3.UP * aim_height
	var eye: Vector3 = _me.get_eye_position()
	var to: Vector3 = target - eye
	var yaw: float = atan2(-to.x, -to.z)
	var pitch: float = atan2(to.y, Vector2(to.x, to.z).length())
	_me.set_look(yaw, pitch)
	_input.aim_held = true
	# Короткими очередями, как живой игрок.
	_input.fire_held = _me.weapon.aim_amount >= 1.0 and fmod(_phase_time, 0.8) < 0.45
	_input.reload_pressed = _me.weapon.ammo == 0
	if _input.fire_held:
		var stats: Vector2i = _hits_per_phase.get(phase, Vector2i.ZERO)
		_hits_per_phase[phase] = stats


func _on_hit_confirmed(headshot: bool, killed: bool) -> void:
	_hits += 1
	var phase: int = maxi(_last_phase, 0)
	var stats: Vector2i = _hits_per_phase.get(phase, Vector2i.ZERO)
	stats.x += 1
	_hits_per_phase[phase] = stats
	if mode == "shooter" or mode == "tdm_shooter":
		_snap.call_deferred("kill" if killed else ("head" if headshot else "hit"))
	print("[test] попадание%s%s (всего %d из %d выстрелов)" % [
		" в голову" if headshot else "", ", УБИТ" if killed else "", _hits, _shots])


# --- Мишень ---------------------------------------------------------------

func _target_tick(delta: float) -> void:
	var phase: int = _me.deaths
	if phase != _last_phase:
		_last_phase = phase
		_phase_time = 0.0
		print("[test] мишень: фаза %d, здоровье %.0f" % [phase, _me.health])
	_phase_time += delta
	_input.move = Vector2.ZERO
	if not _me.alive:
		if _phase_time > 0.3:
			_snap("death")
		return
	if _me.health < Player.MAX_HEALTH and _me.health > 0.0:
		_snap("damaged")
	if phase < 3 and _me.global_position.distance_to(TARGET_SPOT) > 4.0:
		_me.teleport(Transform3D(Basis.IDENTITY, TARGET_SPOT))
		_me.set_look(PI, 0.0)
		return
	if phase == 1:
		# Бег влево-вправо со скоростью ходьбы, разворот каждые ~1.2 с.
		if absf(_me.global_position.x - TARGET_SPOT.x) > 2.5:
			_strafe_dir = -signf(_me.global_position.x - TARGET_SPOT.x)
		_input.move = Vector2(_strafe_dir, 0.0)
	elif phase >= 3:
		if _other == null:
			_other = _find_other()
		if _other != null and _phase_time > 7.0 and _push_start_ms == 0:
			_push_start_ms = Time.get_ticks_msec()
			# Встаём прямо в стрелка.
			_me.teleport(Transform3D(Basis.IDENTITY, _other.global_position))
			print("[test] мишень встала вплотную к стрелку")
		if _phase_time > 12.0:
			_finish("мишень")


# --- TDM ------------------------------------------------------------------

var _tdm_stage: int = 0
var _tdm_stage_time: float = 0.0
var _tdm_mate_hits: int = 0
var _tdm_shots_at_end: int = 0


func _rules() -> TdmRules:
	return TdmRules.get_rules(get_tree())


func _find_by_team(team: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
		var soldier := node as Player
		if soldier != null and soldier != _me and soldier.team == team:
			return soldier
	return null


func _aim_at(target: Player, height: float) -> void:
	var to: Vector3 = target.global_position + Vector3.UP * height - _me.get_eye_position()
	_me.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))


func _tdm_shooter_tick(delta: float) -> void:
	var rules: TdmRules = _rules()
	var mate: Player = _find_by_team(TdmRules.TEAM_BLUE)
	var enemy: Player = _find_by_team(TdmRules.TEAM_RED)
	_tdm_stage_time += delta
	_input.fire_held = false
	_input.aim_held = false
	if _me.alive and _me.global_position.distance_to(SHOOTER_SPOT) > 1.0 and not _me.frozen:
		_me.teleport(Transform3D(Basis.IDENTITY, SHOOTER_SPOT))
	match _tdm_stage:
		0:
			# Ждём обоих и начала раунда.
			if mate != null and enemy != null and rules.phase == TdmRules.Phase.PLAYING \
					and mate.global_position.distance_to(MATE_SPOT) < 1.0 \
					and enemy.global_position.distance_to(ENEMY_SPOT) < 1.0:
				_next_tdm_stage("стреляем в союзника")
		1:
			_aim_at(mate, 1.0)
			_input.aim_held = true
			_input.fire_held = _me.weapon.aim_amount >= 1.0 and fmod(_tdm_stage_time, 0.8) < 0.45
			_input.reload_pressed = _me.weapon.ammo == 0
			if _tdm_stage_time > 4.0:
				print("[test] TDM: по союзнику выстрелов %d, подтверждённых попаданий %d, здоровье союзника %.0f" % [
					_shots, _tdm_mate_hits, mate.health])
				_next_tdm_stage("стреляем во врага")
		2:
			if rules.phase == TdmRules.Phase.ENDED:
				print("[test] TDM: раунд окончен, победитель %s, счёт %d:%d, мои убийства %d, смертей врага %d" % [
					TdmRules.TEAM_NAMES[rules.winner], rules.scores[1], rules.scores[2], _me.kills, enemy.deaths])
				_tdm_shots_at_end = _shots
				_snap("results")
				_next_tdm_stage("итоги: проверяем заморозку")
				return
			if not enemy.alive:
				return
			_aim_at(enemy, 1.0)
			_input.aim_held = true
			_input.fire_held = _me.weapon.aim_amount >= 1.0 and fmod(_tdm_stage_time, 0.8) < 0.45
			_input.reload_pressed = _me.weapon.ammo == 0
		3:
			# На итогах жмём огонь — выстрелов быть не должно.
			_aim_at(enemy, 1.0)
			_input.fire_held = rules.phase == TdmRules.Phase.ENDED
			if rules.phase == TdmRules.Phase.PLAYING:
				print("[test] TDM: выстрелов за время итогов %d (frozen=%s)" % [_shots - _tdm_shots_at_end, _me.frozen])
				_next_tdm_stage("новый раунд")
		4:
			if _tdm_stage_time > 1.5:
				print("[test] TDM: раунд %d, счёт %d:%d, мои убийства %d, смертей врага %d, здоровье врага %.0f" % [
					rules.round_number, rules.scores[1], rules.scores[2], _me.kills, enemy.deaths, enemy.health])
				_finish("tdm")


func _next_tdm_stage(text: String) -> void:
	_tdm_stage += 1
	_tdm_stage_time = 0.0
	print("[test] TDM этап %d: %s" % [_tdm_stage, text])
	if _tdm_stage == 2:
		_tdm_mate_hits = _hits


func _tdm_target_tick(spot: Vector3) -> void:
	var rules: TdmRules = _rules()
	_input.move = Vector2.ZERO
	if _me.alive and _me.global_position.distance_to(spot) > 1.0 and not _me.frozen:
		_me.teleport(Transform3D(Basis.IDENTITY, spot))
		_me.set_look(PI, 0.0)
	if rules.phase == TdmRules.Phase.ENDED:
		_snap("results")
	if rules.round_number >= 2 and rules.phase == TdmRules.Phase.PLAYING and _phase_time == 0.0:
		_phase_time = _time
	if _phase_time > 0.0 and _time - _phase_time > 1.0:
		print("[test] %s: раунд %d, счёт %d:%d, моё здоровье %.0f, смертей %d" % [mode, rules.round_number,
			rules.scores[1], rules.scores[2], _me.health, _me.deaths])
		_finish(mode)


func _tdm_idle_tick() -> void:
	var rules: TdmRules = _rules()
	if rules.phase == TdmRules.Phase.PLAYING and _phase_time == 0.0:
		_phase_time = _time
		print("[test] TDM: раунд начался, лимит %d с" % rules.time_limit)
	if rules.phase == TdmRules.Phase.ENDED:
		print("[test] TDM: раунд окончен по времени через %.1f с, победитель «%s», счёт %d:%d" % [
			_time - _phase_time, TdmRules.TEAM_NAMES[rules.winner], rules.scores[1], rules.scores[2]])
		_finish(mode)


# --- Скриншоты интерфейса (--test=ui, без --team) ------------------------

var _ui_step: int = 0


func _ui_tick() -> void:
	if _ui_step == 0 and _time > 2.5:
		_ui_step = 1
		_snap("team_select")
	elif _ui_step == 1 and _time > 4.0:
		_ui_step = 2
		_rules().request_team(TdmRules.TEAM_BLUE)
	elif _ui_step == 2 and _time > 6.0:
		_ui_step = 3
		_snap("hud")
		Input.action_press(&"player_list")
	elif _ui_step == 3 and _time > 7.0:
		_ui_step = 4
		_snap("scoreboard")
	elif _ui_step == 4 and _time > 8.5:
		Input.action_release(&"player_list")
		_done = true
		get_tree().quit()


# --- Стволы (--test=guns) -------------------------------------------------

var _gun_index: int = -1
var _gun_time: float = 0.0


func _guns_tick(delta: float) -> void:
	_gun_time += delta
	if _gun_index == -1:
		if _time < 1.5:
			return
		_me.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 8.0)))
		_me.set_look(0.0, 0.0)
		_next_gun()
		return
	if _gun_index < WeaponCatalog.WEAPONS.size():
		var data: WeaponData = WeaponCatalog.WEAPONS[_gun_index]
		if _gun_time > 0.8 and _gun_time < 0.9:
			_snap("%02d_%s_hip" % [_gun_index, data.id])
		_input.aim_held = _gun_time > 1.0
		if _gun_time > 1.0 + data.ads_time + 0.4 and not _snapped.has("%02d_%s_ads" % [_gun_index, data.id]):
			_snap("%02d_%s_ads" % [_gun_index, data.id])
		_input.fire_held = _gun_time > 2.0 and _gun_time < 2.05
		if _gun_time > 2.4:
			print("[test] ствол %s: магазин %d/%d, в руках %s, net_weapon %d" % [data.display_name,
				_me.weapon.ammo, data.mag_size, _me.weapon.weapon.display_name, _me.net_weapon])
			_next_gun()
		return
	# Смена на пистолет и обратно клавишами 1/2, потом меню снаряжения.
	match _gun_index - WeaponCatalog.WEAPONS.size():
		0:
			_me.weapon.equip_loadout()
			_input.switch_to = 1
			_gun_index += 1
			_gun_time = 0.0
		1:
			_input.switch_to = -1
			if _gun_time > 0.15 and _gun_time < 0.2:
				_snap("switch_mid")
			if _gun_time > 1.0:
				print("[test] смена: в руках %s (слот %d), идёт смена: %s" % [_me.weapon.weapon.display_name,
					_me.weapon.current_slot, _me.weapon.is_switching])
				_input.switch_to = Player.SWITCH_NEXT
				_gun_index += 1
				_gun_time = 0.0
		2:
			_input.switch_to = -1
			if _gun_time > 1.0:
				print("[test] колесо: в руках %s (слот %d)" % [_me.weapon.weapon.display_name, _me.weapon.current_slot])
				var menu: Node = get_tree().get_first_node_in_group(&"loadout_menu")
				menu.call(&"open")
				_gun_index += 1
				_gun_time = 0.0
		3:
			if _gun_time > 0.5:
				_snap("loadout_menu")
			if _gun_time > 1.0:
				get_tree().get_first_node_in_group(&"loadout_menu").call(&"close")
				var pause: Node = _match.get_node_or_null(^"PauseMenu")
				if pause != null:
					pause.call(&"open")
				_gun_index += 1
				_gun_time = 0.0
		4:
			if _gun_time > 0.5:
				_snap("pause_menu")
			if _gun_time > 1.0:
				_finish("стволы")


func _next_gun() -> void:
	_gun_index += 1
	_gun_time = 0.0
	_input.aim_held = false
	_input.fire_held = false
	if _gun_index < WeaponCatalog.WEAPONS.size():
		var data: WeaponData = WeaponCatalog.WEAPONS[_gun_index]
		_me.weapon.slots[0] = WeaponController.Slot.new(data)
		_me.weapon._select_slot(0, false)


# --- Ощущения (--test=feel) ------------------------------------------------
# Ходьба, повороты камеры, полшага вбок в прицеле. Каждый кадр отрисовки
# пишет: смещение ствола от камеры, где кисть относительно точки хвата,
# и расхождение камеры ствола с основной. Всё это должно быть ровным.

var _feel_stage: int = 0
var _feel_t: float = 0.0
var _feel_log: Dictionary[String, Array] = {}


func _feel_physics() -> void:
	if _me == null:
		_me = _match.get_local_player()
		if _me != null:
			_me.debug_input = _input
		return


func _process(delta: float) -> void:
	if mode != "feel" or _me == null or _done:
		return
	_feel_t += delta
	var stages: Array[String] = ["стоим", "ходьба", "поворот", "прицел", "полшага_в_прицеле", "после"]
	var lengths: Array[float] = [1.0, 2.0, 2.0, 1.0, 0.25, 1.5]
	if _feel_t > lengths[_feel_stage]:
		_feel_t = 0.0
		_feel_stage += 1
		if _feel_stage >= stages.size():
			for key: String in _feel_log:
				var values: Array = _feel_log[key]
				var lo: float = 1e9
				var hi: float = -1e9
				for v: float in values:
					lo = minf(lo, v)
					hi = maxf(hi, v)
				print("[feel] %s: кадров %d, мин %.4f, макс %.4f, размах %.4f" % [key, values.size(), lo, hi, hi - lo])
			_finish("ощущения")
			return
	var stage: String = stages[_feel_stage]
	_input.move = Vector2.ZERO
	_input.aim_held = _feel_stage >= 3
	match stage:
		"ходьба":
			_input.move = Vector2(0, -1)
		"поворот":
			var look: Vector2 = Vector2(_me.net_yaw + 2.5 * delta, 0.0)
			_me.set_look(look.x, 0.0)
		"полшага_в_прицеле":
			_input.move = Vector2(1, 0)
	var weapon: WeaponController = _me.weapon
	var gun: GunView = weapon.get(&"_viewmodel") as GunView
	var arms: FirstPersonArms = weapon.get(&"_arms") as FirstPersonArms
	var camera: Camera3D = _me.get_node(^"Camera3D") as Camera3D
	if gun == null or arms == null:
		return
	_feel_add(stage + ": ствол x", gun.position.x)
	var layer: ViewmodelLayer = _me.get(&"_viewmodel_layer") as ViewmodelLayer
	_feel_add(stage + ": камеры расходятся, м", layer.camera.global_position.distance_to(camera.global_position))
	_feel_current = stage
	if not arms.ik.modification_processed.is_connected(_feel_on_ik):
		arms.ik.modification_processed.connect(_feel_on_ik.bind(arms, weapon))


var _feel_current: String = ""


## Позы после IK видны только в этом сигнале (потом скелет их сбрасывает).
func _feel_on_ik(arms: FirstPersonArms, weapon: WeaponController) -> void:
	var gun: GunView = weapon.get(&"_viewmodel") as GunView
	if gun == null or _feel_current == "":
		return
	var k: Skeleton3D = arms.skeleton
	var palm: Transform3D = k.global_transform * k.get_bone_global_pose(k.find_bone("DEF-hand.R"))
	var in_gun: Vector3 = gun.global_transform.affine_inverse() * palm.origin
	_feel_add(_feel_current + ": запястье в коорд. ствола x", in_gun.x)
	_feel_add(_feel_current + ": запястье в коорд. ствола z", in_gun.z)


func _feel_add(key: String, value: float) -> void:
	if not _feel_log.has(key):
		_feel_log[key] = []
	_feel_log[key].append(value)


# --- Карта «Городок» -----------------------------------------------------

var _town_stage: int = 0
var _town_ramps: Array[Node] = []
var _town_ramp_index: int = 0
var _town_time: float = 0.0
var _town_max_y: float = 0.0
var _town_camera: Camera3D


func _town_tick(delta: float) -> void:
	_town_time += delta
	match _town_stage:
		0:
			if _time < 1.0:
				return
			_check_spawns()
			_town_ramps = get_tree().get_nodes_in_group(&"test_ramp")
			print("[test] карта: пандусов для проверки %d" % _town_ramps.size())
			_town_stage = 1
			_town_time = 0.0
			_town_ramp_index = -1
			_next_ramp()
		1:
			_input.move = Vector2(0, -1)
			_town_max_y = maxf(_town_max_y, _me.global_position.y)
			if _town_time > 5.0:
				var marker := _town_ramps[_town_ramp_index] as Marker3D
				var top: float = float(marker.get_meta(&"top_height", 3.3))
				print("[test] пандус %s: высота наверху %.2f м (нужно %.2f) — %s" % [marker.name, _town_max_y, top,
					"OK" if _town_max_y >= top - 0.1 else "НЕ ДОШЁЛ"])
				_snap("ramp_%d" % _town_ramp_index)
				_next_ramp()
		2:
			_input.move = Vector2.ZERO
			if _screens_dir.is_empty() or DisplayServer.get_name() == "headless":
				_finish("карта")
				return
			_town_screens()


func _check_spawns() -> void:
	var space: PhysicsDirectSpaceState3D = _me.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	for team: int in [1, 2]:
		var points: Array[Node] = get_tree().get_nodes_in_group(StringName("spawn_team_%d" % team))
		var bad: int = 0
		for node: Node in points:
			var point := node as Node3D
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 1 | 4
			query.transform = Transform3D(Basis.IDENTITY, point.global_position + Vector3.UP * 0.96)
			var overlap: Array[Dictionary] = space.intersect_shape(query, 4)
			var ray := PhysicsRayQueryParameters3D.create(point.global_position + Vector3.UP * 0.5,
					point.global_position + Vector3.DOWN * 0.5, 1)
			var ground: Dictionary = space.intersect_ray(ray)
			if not overlap.is_empty() or ground.is_empty():
				bad += 1
				print("[test] плохая точка спавна %s: пересечений %d, земля %s" % [point.get_path(), overlap.size(), not ground.is_empty()])
		var forward: Vector3 = -(points[0] as Node3D).global_basis.z
		print("[test] спавны команды %d: %d точек, плохих %d, смотрят на %s" % [team, points.size(), bad,
			str(forward.snapped(Vector3.ONE * 0.01))])


func _next_ramp() -> void:
	_town_ramp_index += 1
	_town_time = 0.0
	_town_max_y = 0.0
	if _town_ramp_index >= _town_ramps.size():
		_town_stage = 2
		_town_time = 0.0
		return
	var marker := _town_ramps[_town_ramp_index] as Marker3D
	_me.teleport(marker.global_transform)
	_me.set_look(marker.global_rotation.y, -0.2)


var _town_shot_index: int = -1

func _town_screens() -> void:
	# [имя, позиция камеры, точка, куда смотрим]
	var shots: Array[Array] = [
		["overview", Vector3(-20, 85, 75), Vector3(0, 0, 0)],
		["overview_west", Vector3(-95, 35, 30), Vector3(-30, 0, 0)],
		["street_blue", Vector3(-50, 1.6, 1.0), Vector3(0, 1.5, 0)],
		["crossroad", Vector3(-6, 1.6, -9), Vector3(10, 1.0, 6)],
		["north_yards", Vector3(-46, 1.6, -27), Vector3(-20, 1, -15)],
		["inside_two_storey", Vector3(-22.5, FLOOR_HEIGHT_TEST + 1.6, -11.5), Vector3(-29, 2.5, -15)],
		["south_block", Vector3(-30, 1.6, 6.2), Vector3(-12, 1.0, 15)],
		["blue_base", Vector3(-73, 2.2, 12), Vector3(-55, 1, -5)],
	]
	if _town_camera == null:
		_town_camera = Camera3D.new()
		_town_camera.fov = 75.0
		_town_camera.far = 800.0
		add_child(_town_camera)
		_town_camera.current = true
	if _town_time < 0.6:
		return
	_town_time = 0.0
	_town_shot_index += 1
	if _town_shot_index >= shots.size():
		_finish("карта")
		return
	var shot: Array = shots[_town_shot_index]
	_town_camera.global_position = shot[1] as Vector3
	_town_camera.look_at(shot[2] as Vector3, Vector3.UP)
	_snapped.erase(str(shot[0]))
	_snap.call_deferred(str(shot[0]))


func _snap(shot_name: String) -> void:
	if _screens_dir.is_empty() or _snapped.has(shot_name) or DisplayServer.get_name() == "headless":
		return
	_snapped[shot_name] = true
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s_%s.png" % [_screens_dir, mode, shot_name]
	get_viewport().get_texture().get_image().save_png(path)
	print("[test] скриншот %s" % path)


func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	var lines := PackedStringArray()
	for phase: int in _hits_per_phase:
		lines.append("фаза %d: попаданий %d" % [phase, _hits_per_phase[phase].x])
	print("[test] ИТОГ (%s): выстрелов %d, попаданий %d; %s; моё здоровье %.0f, мои смерти %d, убийства %d" % [
		reason, _shots, _hits, ", ".join(lines), _me.health if _me != null else -1.0,
		_me.deaths if _me != null else -1, _me.kills if _me != null else -1])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
