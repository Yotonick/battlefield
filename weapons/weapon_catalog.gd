class_name WeaponCatalog
extends RefCounted
## Список всех стволов игры. Номер в списке — то, что передаётся по сети
## (короче строки), поэтому новые стволы добавляем только в КОНЕЦ списка.
##
## Выбор игрока (основной + пистолет) хранится на его ПК в user://loadout.cfg.
## Хост этот выбор не проверяет: игра для друзей (как и со стрельбой).

const WEAPONS: Array[WeaponData] = [
	preload("res://weapons/data/rifle_ak.tres"),
	preload("res://weapons/data/rifle_m4a1.tres"),
	preload("res://weapons/data/rifle_m16.tres"),
	preload("res://weapons/data/rifle_scar.tres"),
	preload("res://weapons/data/smg_mp5.tres"),
	preload("res://weapons/data/smg_mp7.tres"),
	preload("res://weapons/data/shotgun_pump.tres"),
	preload("res://weapons/data/sniper_bolt.tres"),
	preload("res://weapons/data/pistol_m1911.tres"),
	preload("res://weapons/data/pistol_m1911_tactical.tres"),
]

const DEFAULT_PRIMARY: StringName = &"rifle_ak"
const DEFAULT_SECONDARY: StringName = &"pistol_m1911"
const SAVE_PATH: String = "user://loadout.cfg"

## Выбранное снаряжение этого игрока (меняется в меню снаряжения).
static var primary_id: StringName = DEFAULT_PRIMARY
static var secondary_id: StringName = DEFAULT_SECONDARY
static var _loaded: bool = false


static func get_index(weapon_id: StringName) -> int:
	for i: int in WEAPONS.size():
		if WEAPONS[i].id == weapon_id:
			return i
	return -1


static func get_by_index(index: int) -> WeaponData:
	if index < 0 or index >= WEAPONS.size():
		return null
	return WEAPONS[index]


static func get_by_id(weapon_id: StringName) -> WeaponData:
	return get_by_index(get_index(weapon_id))


static func list_slot(slot: WeaponData.Slot) -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for weapon: WeaponData in WEAPONS:
		if weapon.slot == slot:
			result.append(weapon)
	return result


## Снаряжение для появления: [основной, пистолет].
static func get_loadout() -> Array[WeaponData]:
	load_loadout()
	var primary: WeaponData = get_by_id(primary_id)
	var secondary: WeaponData = get_by_id(secondary_id)
	if primary == null or primary.slot != WeaponData.Slot.PRIMARY:
		primary = get_by_id(DEFAULT_PRIMARY)
	if secondary == null or secondary.slot != WeaponData.Slot.SECONDARY:
		secondary = get_by_id(DEFAULT_SECONDARY)
	var result: Array[WeaponData] = [primary, secondary]
	return result


static func set_choice(weapon: WeaponData) -> void:
	load_loadout()
	if weapon.slot == WeaponData.Slot.PRIMARY:
		primary_id = weapon.id
	else:
		secondary_id = weapon.id
	var config := ConfigFile.new()
	config.set_value("loadout", "primary", String(primary_id))
	config.set_value("loadout", "secondary", String(secondary_id))
	config.save(SAVE_PATH)


static func load_loadout() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		primary_id = StringName(str(config.get_value("loadout", "primary", String(DEFAULT_PRIMARY))))
		secondary_id = StringName(str(config.get_value("loadout", "secondary", String(DEFAULT_SECONDARY))))
	# Для тестов: --primary=smg_mp5 --secondary=pistol_m1911 (не сохраняется).
	var args := PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--primary="):
			primary_id = StringName(arg.trim_prefix("--primary="))
		elif arg.begins_with("--secondary="):
			secondary_id = StringName(arg.trim_prefix("--secondary="))
