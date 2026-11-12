class_name DebugOverlay
extends CanvasLayer
## Отладочная информация о локальном бойце. F3 — показать/скрыть.

@onready var _label: Label = $Label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var player := get_tree().get_first_node_in_group(Player.LOCAL_PLAYER_GROUP) as Player
	if player == null:
		_label.text = "FPS: %d\nнет локального бойца" % Engine.get_frames_per_second()
		return

	var fmt: String = "\n".join([
		"FPS: %d",
		"скорость: %.2f м/с",
		"по вертикали: %.2f м/с",
		"поза: %s%s",
		"на земле: %s",
		"позиция: %s",
	])
	_label.text = fmt % [
		Engine.get_frames_per_second(),
		player.get_horizontal_speed(),
		player.velocity.y,
		"присед" if player.stance == Player.Stance.CROUCH else "стоя",
		" + бег" if player.is_sprinting else "",
		"да" if player.is_on_floor() else "нет",
		str(player.global_position.snapped(Vector3.ONE * 0.01)),
	]
