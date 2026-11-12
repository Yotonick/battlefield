class_name WeaponData
extends Resource
## Параметры оружия. Один файл `.tres` = один ствол.
## Все углы — в градусах, расстояния — в метрах, время — в секундах.

enum Slot { PRIMARY, SECONDARY }
enum FireMode { AUTO, SEMI, BURST }
## Обзор, для которого заданы ads_fov.
const ADS_FOV_REFERENCE: float = 80.0
enum Category { ASSAULT, CARBINE, BATTLE, SMG, SHOTGUN, SNIPER, PISTOL }

const CATEGORY_NAMES: Array[String] = ["Автомат", "Карабин", "Боевая винтовка", "Пистолет-пулемёт",
		"Дробовик", "Снайперская винтовка", "Пистолет"]

@export var id: StringName = &"rifle"
@export var display_name: String = "Автомат"
@export var slot: Slot = Slot.PRIMARY
@export var category: Category = Category.ASSAULT
## Короткое описание для меню снаряжения.
@export_multiline var description: String = ""

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
@export var fire_mode: FireMode = FireMode.AUTO
## Выстрелов в очереди (для BURST).
@export var burst_count: int = 3
## Пауза после очереди перед следующей, с.
@export var burst_delay: float = 0.25
## Дробинок за выстрел (1 — обычная пуля). Урон указан на одну дробинку.
@export var pellets: int = 1
## Разлёт дроби, градусов (вокруг точки, куда ушёл бы обычный выстрел).
@export var pellet_spread: float = 0.0
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
## Обзор в прицеле при настройке обзора 80° (при другой — пропорционально).
@export var ads_fov: float = 55.0
## Оптика: в прицеле модель скрывается, на экране — круг прицела.
@export var has_scope: bool = false
## Время подъёма прицела.
@export var ads_time: float = 0.18
## Скорость ходьбы в прицеле (множитель).
@export var ads_move_multiplier: float = 0.6
## Время доставания оружия при смене.
@export var draw_time: float = 0.45

@export_group("Модель")
## Модель ствола (любая ориентация — см. model_yaw_deg).
@export var model: PackedScene
## Длина ствола в игре, м. Модель масштабируется под неё.
@export var model_length: float = 0.9
## Поворот модели вокруг вертикали, чтобы дуло смотрело в −Z.
@export var model_yaw_deg: float = 0.0
## Поворот модели вокруг оси ствола (180 — если модель в файле вверх ногами).
@export var model_roll_deg: float = 0.0
## Насколько линия прицела ниже верха модели, м.
@export var sight_drop: float = 0.012
## Насколько дуло ниже верха модели (доля высоты модели).
@export_range(0.0, 1.0) var muzzle_drop: float = 0.3
## Насколько задний край модели позади линии взгляда в прицеле, м.
@export var rear_offset: float = 0.22
## Положение модели у камеры: от бедра и в прицеле.
@export var view_hip: Vector3 = Vector3(0.15, -0.125, -0.27)
## Поворот от бедра, градусы (y > 0 — дуло к центру экрана).
@export var view_hip_rot_deg: Vector3 = Vector3(1.0, 5.0, -3.0)
@export var view_ads: Vector3 = Vector3(0.0, 0.0, -0.3)

@export_group("Хват")
## Точки хвата в координатах ствола (после выравнивания GunView: дуло в −Z,
## линия прицела y = 0): середина ладони правой руки на рукоятке
## и левой — на цевье. Подбираются по виду сбоку (tests/viewmodel_preview.gd --side).
@export var grip_right: Vector3 = Vector3(0.0, -0.075, 0.02)
@export var grip_left: Vector3 = Vector3(-0.005, -0.09, -0.3)
## Направление пальцев правой кисти (от запястья к костяшкам).
@export var grip_right_fingers: Vector3 = Vector3(0.0, -0.6, -0.8)
## Левая кисть: направление пальцев и куда смотрит ладонь.
@export var grip_left_fingers: Vector3 = Vector3(0.55, 0.15, -0.8)
@export var grip_left_palm: Vector3 = Vector3(0.2, 1.0, 0.0)
## Плечи рук от первого лица в координатах ствола (ниже и позади поля зрения).
@export var shoulder_right: Vector3 = Vector3(0.11, -0.3, 0.42)
@export var shoulder_left: Vector3 = Vector3(-0.27, -0.24, 0.17)


func get_damage(distance: float, headshot: bool) -> float:
	var t: float = clampf(inverse_lerp(falloff_start, falloff_end, distance), 0.0, 1.0)
	var damage: float = lerpf(damage_close, damage_far, t)
	return damage * (headshot_multiplier if headshot else 1.0)


func is_automatic() -> bool:
	return fire_mode == FireMode.AUTO


func get_shot_interval() -> float:
	return 60.0 / maxf(fire_rate_rpm, 1.0)
