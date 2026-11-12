class_name GameSettings
extends RefCounted
## Настройки игрока на этом ПК (user://settings.cfg): угол обзора, чувствительность.
## Значения статические — читаются один раз при первом обращении.

const PATH: String = "user://settings.cfg"
## Угол обзора по вертикали (как Camera3D.fov). Узкий диапазон — по решению
## владельца, чтобы широкий обзор не давал преимущества.
const FOV_MIN: float = 60.0
const FOV_MAX: float = 80.0
const FOV_DEFAULT: float = 70.0
const SENS_MIN: float = 0.03
const SENS_MAX: float = 0.4
const SENS_DEFAULT: float = 0.12

static var _loaded: bool = false
static var _fov: float = FOV_DEFAULT
static var _sensitivity: float = SENS_DEFAULT


static func get_fov() -> float:
	_ensure_loaded()
	return _fov


static func set_fov(value: float) -> void:
	_ensure_loaded()
	_fov = clampf(value, FOV_MIN, FOV_MAX)
	_save()


static func get_sensitivity() -> float:
	_ensure_loaded()
	return _sensitivity


static func set_sensitivity(value: float) -> void:
	_ensure_loaded()
	_sensitivity = clampf(value, SENS_MIN, SENS_MAX)
	_save()


## Горизонтальный угол для подписи в меню (при соотношении сторон экрана).
static func horizontal_fov(vertical_deg: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_deg) * 0.5) * aspect))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	_fov = clampf(float(config.get_value("view", "fov", FOV_DEFAULT)), FOV_MIN, FOV_MAX)
	_sensitivity = clampf(float(config.get_value("input", "sensitivity", SENS_DEFAULT)), SENS_MIN, SENS_MAX)


static func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("view", "fov", _fov)
	config.set_value("input", "sensitivity", _sensitivity)
	config.save(PATH)
