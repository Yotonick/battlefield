extends CanvasLayer
## Сетевой интерфейс в бою: «Подключение…», лента «зашёл/вышел»,
## список игроков по Tab (пока Tab зажат).

const FEED_LIFETIME: float = 6.0
const FEED_MAX_LINES: int = 6

@onready var _status: Label = %Status
@onready var _feed: VBoxContainer = %Feed
@onready var _list_center: CenterContainer = %ListCenter
@onready var _list: Label = %List


func _ready() -> void:
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.player_list_changed.connect(_refresh_list)
	if not Network.is_host():
		_status.text = "Подключение к %s…" % Network.last_join_address


func _process(_delta: float) -> void:
	# Пока не появился свой боец — показываем статус подключения.
	if not _status.text.is_empty() and get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) != null:
		_status.text = ""
	var show_list: bool = Input.is_action_pressed(&"player_list")
	if show_list != _list_center.visible:
		_list_center.visible = show_list
	if show_list:
		_refresh_list()  # счёт меняется во время боя


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


func _refresh_list() -> void:
	if not _list_center.visible:
		return
	var lines := PackedStringArray()
	lines.append("Игроки: %d / %d" % [Network.players.size(), Network.MAX_PLAYERS])
	lines.append("")
	var my_id: int = multiplayer.get_unique_id()
	var scores: Dictionary[int, Vector2i] = {}
	for node: Node in get_tree().get_nodes_in_group(Player.PLAYERS_GROUP):
		var soldier := node as Player
		if soldier != null:
			scores[soldier.peer_id] = Vector2i(soldier.kills, soldier.deaths)
	for peer_id: int in Network.players:
		var tags := PackedStringArray()
		if peer_id == 1:
			tags.append("хост")
		if peer_id == my_id:
			tags.append("вы")
		var suffix: String = "" if tags.is_empty() else "  (%s)" % ", ".join(tags)
		var score: Vector2i = scores.get(peer_id, Vector2i.ZERO)
		lines.append("%s%s    убийств %d / смертей %d" % [Network.players[peer_id], suffix, score.x, score.y])
	if not Network.is_host():
		lines.append("")
		lines.append("Пинг до хоста: %d мс" % Network.get_ping_ms())
	_list.text = "\n".join(lines)
