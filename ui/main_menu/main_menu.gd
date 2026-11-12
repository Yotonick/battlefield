extends Control
## Главное меню: имя, «Создать игру», «Подключиться по IP».

@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _status: Label = %Status
@onready var _addresses: Label = %Addresses
@onready var _version: Label = %Version


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

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_host_button.grab_focus()


func _on_host_pressed() -> void:
	_store_name()
	Network.request_host()


func _on_join_pressed() -> void:
	if _address_edit.text.strip_edges().is_empty():
		_status.text = "Введите IP хоста."
		return
	_store_name()
	Network.request_join(_address_edit.text)


func _store_name() -> void:
	Network.player_name = _name_edit.text.strip_edges().left(Network.MAX_NAME_LENGTH)
