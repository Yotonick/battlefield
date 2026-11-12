class_name ViewmodelLayer
extends CanvasLayer
## Ствол (и руки) от первого лица рисуются отдельной камерой поверх мира.
##
## Зачем: у основной камеры широкий обзор (60–80° по вертикали) — в углу
## экрана предметы сильно растягиваются, ствол выглядит мелким и «сплющенным».
## Здесь свой узкий FOV, одинаковый при любой настройке обзора, и ствол
## не проходит сквозь стены (мир этой камерой не рисуется).
##
## Модели от первого лица кладутся на визуальный слой VISUAL_LAYER
## (GunView.set_first_person), основная камера этот слой не видит.

## Визуальный слой 11.
const VISUAL_LAYER: int = 1 << 10
## Обзор камеры ствола от бедра и в прицеле (по вертикали).
const HIP_FOV: float = 50.0
const ADS_FOV: float = 42.0

var camera: Camera3D
var _source: Camera3D
var _viewport: SubViewport
var _light_check: float = 0.0


func _init(source: Camera3D) -> void:
	name = "ViewmodelLayer"
	_source = source
	layer = 1  # над миром, под HUD (у HUD слои 4+)
	_source.cull_mask &= ~VISUAL_LAYER

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.audio_listener_enable_3d = false
	container.add_child(_viewport)

	camera = Camera3D.new()
	# Положение камеры ставится каждый кадр отрисовки — интерполяция физики
	# здесь только мешает (камера отставала бы от основной и «догоняла»).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.cull_mask = VISUAL_LAYER
	camera.near = 0.01
	camera.far = 10.0
	camera.fov = HIP_FOV
	_viewport.add_child(camera)


func _ready() -> void:
	camera.current = true
	_include_lights()


## Камера рисует только объекты своего слоя — свет тоже отсекается по слоям.
## Поэтому солнце (и другие направленные источники) карты добавляем в этот слой.
## Карта у клиента грузится позже бойца — проверяем раз в секунду.
func _include_lights() -> void:
	for node: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		light.layers |= VISUAL_LAYER


func _process(delta: float) -> void:
	_light_check -= delta
	if _light_check <= 0.0:
		_light_check = 1.0
		_include_lights()


## Вызывается бойцом после того, как он поставил основную камеру.
func sync(aim_amount: float) -> void:
	camera.global_transform = _source.global_transform
	var t: float = aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
	camera.fov = lerpf(HIP_FOV, ADS_FOV, t)
