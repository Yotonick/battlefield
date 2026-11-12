class_name WeaponData
extends Resource
## Параметры оружия. Один файл `.tres` = один ствол.
## Все углы — в градусах, расстояния — в метрах, время — в секундах.

@export var id: StringName = &"rifle"
@export var display_name: String = "Автомат"

@export_group("Урон")
## Урон в тело вблизи (до falloff_start).
@export var damage_close: float = 25.0
## Урон в тело далеко (после falloff_end).
@export var damage_far: float = 18.0
@export var falloff_start: float = 40.0
@export var falloff_end: float = 120.0
## Множитель урона в голову.
@export var headshot_multiplier: float = 1.8

@export_group("Пуля")
## Скорость пули на вылете, м/с.
@export var muzzle_velocity: float = 715.0
## 1.0 — обычная гравитация (9.8 м/с²).
@export var gravity_scale: float = 1.0
## Через сколько секунд полёта пуля исчезает.
@export var bullet_lifetime: float = 3.0

@export_group("Стрельба")
## Выстрелов в минуту.
@export var fire_rate_rpm: float = 600.0
@export var mag_size: int = 30
## Патронов в запасе при спавне (не считая магазина).
@export var reserve_ammo: int = 120
## Перезарядка, когда в магазине ещё есть патрон.
@export var reload_time: float = 2.2
## Перезарядка пустого магазина (нужно ещё передёрнуть затвор).
@export var reload_empty_time: float = 2.7
## Сколько времени после бега нельзя стрелять.
@export var sprint_to_fire_time: float = 0.15

@export_group("Разброс")
@export var spread_hip: float = 1.4
@export var spread_ads: float = 0.1
## Прибавка за каждый выстрел.
@export var spread_per_shot: float = 0.22
## Максимум накопленной прибавки.
@export var spread_max_extra: float = 2.2
## Как быстро прибавка уходит, градусов в секунду.
@export var spread_recovery: float = 7.0
## Множитель разброса на ходу (при полной скорости ходьбы).
@export var spread_move_multiplier: float = 1.8
## Множитель разброса сидя.
@export var spread_crouch_multiplier: float = 0.7
## Разброс в прыжке.
@export var spread_air: float = 6.0

@export_group("Отдача")
## Подброс ствола вверх за выстрел.
@export var recoil_vertical: float = 0.55
## Случайный увод влево-вправо за выстрел (±).
@export var recoil_horizontal: float = 0.3
## Множитель отдачи в прицеле.
@export var recoil_ads_multiplier: float = 0.75
## Сколько процентов подброса камера возвращает сама, когда перестали стрелять.
@export_range(0.0, 1.0) var recoil_recovery: float = 0.4

@export_group("Прицеливание")
@export var ads_fov: float = 55.0
## Время подъёма прицела.
@export var ads_time: float = 0.18
## Скорость ходьбы в прицеле (множитель).
@export var ads_move_multiplier: float = 0.6


func get_damage(distance: float, headshot: bool) -> float:
	var t: float = clampf(inverse_lerp(falloff_start, falloff_end, distance), 0.0, 1.0)
	var damage: float = lerpf(damage_close, damage_far, t)
	return damage * (headshot_multiplier if headshot else 1.0)


func get_shot_interval() -> float:
	return 60.0 / maxf(fire_rate_rpm, 1.0)
