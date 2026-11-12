class_name MatchSettings
extends RefCounted
## Настройки матча, которые выбирает хост в главном меню:
## карта, лимит убийств, время раунда. Хост отправляет их каждому
## подключившемуся (Network._receive_match_settings).

const MAPS: Dictionary[String, String] = {
	"town": "res://maps/town/town.tscn",
	"test_range": "res://maps/test_range/test_range.tscn",
}
const MAP_TITLES: Dictionary[String, String] = {
	"town": "Городок",
	"test_range": "Полигон (проверка движения)",
}
const DEFAULT_MAP: String = "town"
const DEFAULT_KILL_LIMIT: int = 30
const DEFAULT_TIME_LIMIT: int = 600
const MIN_KILL_LIMIT: int = 1
const MAX_KILL_LIMIT: int = 500
const MIN_TIME_LIMIT: int = 5
const MAX_TIME_LIMIT: int = 3600
## Сколько секунд показывать итоги раунда перед новым.
const DEFAULT_RESULTS_TIME: float = 15.0

var map_id: String = DEFAULT_MAP
## Сколько убийств нужно команде для победы.
var kill_limit: int = DEFAULT_KILL_LIMIT
## Длина раунда, секунд.
var time_limit: int = DEFAULT_TIME_LIMIT
var results_time: float = DEFAULT_RESULTS_TIME


func get_map_path() -> String:
	return MAPS.get(map_id, MAPS[DEFAULT_MAP])


func to_dict() -> Dictionary:
	return {
		"map": map_id,
		"kills": kill_limit,
		"time": time_limit,
		"results": results_time,
	}


## Значения с проверкой: от клиента/из файла может прийти что угодно.
func apply_dict(data: Dictionary) -> void:
	var map_value: String = str(data.get("map", map_id))
	map_id = map_value if MAPS.has(map_value) else DEFAULT_MAP
	kill_limit = clampi(int(data.get("kills", kill_limit)), MIN_KILL_LIMIT, MAX_KILL_LIMIT)
	time_limit = clampi(int(data.get("time", time_limit)), MIN_TIME_LIMIT, MAX_TIME_LIMIT)
	results_time = clampf(float(data.get("results", results_time)), 2.0, 60.0)
