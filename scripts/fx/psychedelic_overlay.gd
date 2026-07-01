extends CanvasLayer
## Full-screen psychedelic post-process. Intensity tracks GameManager's score-driven
## value, but is forced to zero during instant replays per the game's twist:
## replays are shown "clean" while the live game gets trippier as it goes on.

var _rect: ColorRect
var _material: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	layer = 50
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	var shader: Shader = load("res://shaders/psychedelic.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material


func _process(delta: float) -> void:
	_time += delta
	var target_intensity := 0.0
	if not ReplayManager.is_replaying:
		target_intensity = GameManager.psychedelic_intensity
	_material.set_shader_parameter("intensity", target_intensity)
	_material.set_shader_parameter("time_seconds", _time)
