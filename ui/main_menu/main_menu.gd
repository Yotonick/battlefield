extends Control
## Главное меню: имя, настройки матча (для хоста), «Создать игру»,
## «Подключиться по IP».

@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _status: Label = %Status
@onready var _addresses: Label = %Addresses
@onready var _version: Label = %Version

var _map_option: OptionButton
var _kills_spin: SpinBox
var _time_spin: SpinBox


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().title = "Battlefield"

	_name_edit.text = Network.player_name
	_address_edit.text = Network.last_join_address
	_version.text = "версия %s" % str(ProjectSettings.get_setting("application/config/version", "dev"))
	_status.text = Network.last_end_reason
	Network.last_end_reason = ""

	var local_addresses: PackedStringArray = Network.get_local_ipv4_addresses()
	if local_addresses.is_empty():
		_addresses.text = "Сетевых адресов не найдено."
	else:
		_addresses.text = "Адреса этого компьютера (их сообщить друзьям, если вы хост): %s" % ", ".join(local_addresses)

	_build_match_settings()
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_host_button.grab_focus()


func _on_host_pressed() -> void:
	_store_name()
	var settings: MatchSettings = Network.match_settings
	settings.map_id = str(_map_option.get_item_metadata(_map_option.selected))
	settings.kill_limit = int(_kills_spin.value)
	settings.time_limit = int(_time_spin.value) * 60
	Network.request_host()


func _on_join_pressed() -> void:
	if _address_edit.text.strip_edges().is_empty():
		_status.text = "Введите IP хоста."
		return
	_store_name()
	Network.request_join(_address_edit.text)


func _store_name() -> void:
	Network.player_name = _name_edit.text.strip_edges().left(Network.MAX_NAME_LENGTH)


## Настройки матча — над кнопкой «Создать игру» (их видит только хост;
## клиенты получают их от хоста).
func _build_match_settings() -> void:
	var settings: MatchSettings = Network.match_settings
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 6)

	grid.add_child(_settings_label("Карта"))
	_map_option = OptionButton.new()
	_map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in MatchSettings.MAPS:
		_map_option.add_item(MatchSettings.MAP_TITLES.get(id, id))
		_map_option.set_item_metadata(_map_option.item_count - 1, id)
		if id == settings.map_id:
			_map_option.select(_map_option.item_count - 1)
	grid.add_child(_map_option)

	grid.add_child(_settings_label("Убийств для победы"))
	_kills_spin = SpinBox.new()
	_kills_spin.min_value = 5
	_kills_spin.max_value = 200
	_kills_spin.step = 5
	_kills_spin.value = clampi(settings.kill_limit, 5, 200)
	grid.add_child(_kills_spin)

	grid.add_child(_settings_label("Время раунда, мин"))
	_time_spin = SpinBox.new()
	_time_spin.min_value = 1
	_time_spin.max_value = 60
	_time_spin.value = clampi(settings.time_limit / 60, 1, 60)
	grid.add_child(_time_spin)

	var vbox: Node = _host_button.get_parent()
	var caption := _settings_label("Командный бой (TDM) — настройки хоста")
	caption.add_theme_color_override(&"font_color", Color(0.65, 0.67, 0.63))
	vbox.add_child(caption)
	vbox.move_child(caption, _host_button.get_index())
	vbox.add_child(grid)
	vbox.move_child(grid, _host_button.get_index())


func _settings_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
