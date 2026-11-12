extends CanvasLayer
## Сетевой интерфейс в бою: «Подключение…», лента «зашёл/вышел».
## Список игроков по Tab — в TdmHud (по командам).

const FEED_LIFETIME: float = 6.0
const FEED_MAX_LINES: int = 6

@onready var _status: Label = %Status
@onready var _feed: VBoxContainer = %Feed


func _ready() -> void:
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	if not Network.is_host():
		_status.text = "Подключение к %s…" % Network.last_join_address


func _process(_delta: float) -> void:
	# Пока хост не принял нас в игру — показываем статус подключения.
	if not _status.text.is_empty():
		var rules: TdmRules = TdmRules.get_rules(get_tree())
		if rules != null and rules.teams.has(multiplayer.get_unique_id()):
			_status.text = ""


func _on_player_joined(peer_id: int, player_name: String) -> void:
	if peer_id != multiplayer.get_unique_id():
		_add_feed_line("%s подключился" % player_name)


func _on_player_left(_peer_id: int, player_name: String) -> void:
	_add_feed_line("%s вышел" % player_name)


func _add_feed_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	label.add_theme_font_size_override(&"font_size", 17)
	_feed.add_child(label)
	while _feed.get_child_count() > FEED_MAX_LINES:
		_feed.get_child(0).free()
	var tween: Tween = label.create_tween()
	tween.tween_interval(FEED_LIFETIME)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
