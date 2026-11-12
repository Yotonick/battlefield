extends Node
## Автотест боя (запускается только с аргументом --test=…, в игре не участвует).
##
##   --test=ballistics   один хост: выстрел без разброса в столб на 100 м,
##                       печатает точку попадания и падение пули.
##   --test=shooter      стреляет в другого бойца (роль хоста или клиента — любая)
##   --test=target       мишень: стоит, бегает влево-вправо, потом встаёт вплотную
##   --test=observer     подключиться позже и напечатать здоровье/счёт всех бойцов
##
## Фазы мишени по числу её смертей: 0 — стоит (в тело), 1 — бегает (в тело),
## 2 — стоит (в голову), 3 — подходит вплотную к стрелку (проверка расталкивания).

const TARGET_SPOT := Vector3(0.0, 0.05, -12.0)
const SHOOTER_SPOT := Vector3(0.0, 0.05, 8.0)
const TIMEOUT: float = 75.0

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


func _ready() -> void:
	_match = get_parent() as Match
	print("[test] режим %s" % mode)
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
		"observer":
			if _time > 3.0:
				for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
					var soldier := node as Player
					print("[test] наблюдатель: %s — здоровье %.0f, жив %s, убийств %d, смертей %d" % [
						soldier.display_name, soldier.health, soldier.alive, soldier.kills, soldier.deaths])
				_finish("наблюдатель")


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
	if mode == "shooter":
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
