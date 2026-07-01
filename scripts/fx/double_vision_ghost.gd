extends Node3D
class_name DoubleVisionGhost
## Attach as a child of any Node3D and point `target` at a *plain* visual-only
## node (no gameplay script attached) — e.g. an imported character model
## instance, or a "Visual" wrapper around a primitive mesh. Duplicates that
## node wholesale (preserving skin/skeleton bindings for rigged characters),
## tints the copy translucent, and drifts it as GameManager's psychedelic
## intensity rises, producing a "double vision" effect. Hidden entirely
## during instant replays, since replays are exempt from psychedelic FX.
##
## `target` must not carry a script that reacts to _ready()/registration
## (autoload registration, further ghost spawning, etc.) — duplicating it
## would re-run that logic and recurse. Plain visual nodes have no script.

@export var target: Node3D
@export var max_offset: float = 0.12
@export var drift_speed: float = 1.4

var _ghost_root: Node3D
var _phase: float = randf() * TAU


func _ready() -> void:
	if target == null:
		target = get_parent()
	# Deferred so the target has finished building/instancing itself first.
	call_deferred("_build_ghost")


func _build_ghost() -> void:
	if not is_instance_valid(target):
		return
	_ghost_root = target.duplicate()
	add_child(_ghost_root)
	_tint_translucent(_ghost_root)


func _tint_translucent(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.95, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint_translucent(child)


func _process(delta: float) -> void:
	if not is_instance_valid(_ghost_root):
		return

	if ReplayManager.is_replaying:
		_ghost_root.visible = false
		return

	var intensity: float = GameManager.psychedelic_intensity
	if intensity <= 0.001:
		_ghost_root.visible = false
		return

	_ghost_root.visible = true
	_phase += delta * drift_speed
	var offset := Vector3(
		sin(_phase) * max_offset * intensity,
		sin(_phase * 1.3 + 1.0) * max_offset * 0.4 * intensity,
		cos(_phase * 0.8) * max_offset * intensity
	)
	_ghost_root.position = offset
	_update_alpha(_ghost_root, 0.45 * intensity)


func _update_alpha(node: Node, alpha: float) -> void:
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = node.material_override
		var col := mat.albedo_color
		col.a = alpha
		mat.albedo_color = col
	for child in node.get_children():
		_update_alpha(child, alpha)
