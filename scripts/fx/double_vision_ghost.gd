extends Node3D
class_name DoubleVisionGhost
## Attach as a child of any Node3D that has MeshInstance3D descendants
## (players, the ball, the hoop). Spawns a translucent duplicate of those
## meshes that drifts away from the original as GameManager's psychedelic
## intensity rises, producing a "double vision" effect. Hidden entirely
## during instant replays, since replays are exempt from psychedelic FX.

@export var target: Node3D
@export var max_offset: float = 0.12
@export var drift_speed: float = 1.4

var _ghost_root: Node3D
var _phase: float = randf() * TAU


func _ready() -> void:
	if target == null:
		target = get_parent()
	# Deferred so the target has finished building its own mesh children first.
	call_deferred("_build_ghost")


func _build_ghost() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.name = "DoubleVisionGhost"
	add_child(_ghost_root)
	_clone_meshes(target, _ghost_root)


func _clone_meshes(source: Node, dest_parent: Node3D) -> void:
	for child in source.get_children():
		# Skip our own ghost subtree (and any sibling ghost components) so we
		# don't recursively clone the clones when `target` is our own parent.
		if child is DoubleVisionGhost or child == _ghost_root:
			continue
		if child is MeshInstance3D:
			var clone := MeshInstance3D.new()
			clone.mesh = child.mesh
			clone.transform = child.transform
			var ghost_mat := StandardMaterial3D.new()
			ghost_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
			ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ghost_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.4)
			clone.material_override = ghost_mat
			clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dest_parent.add_child(clone)
		elif child is Node3D and child.get_child_count() > 0:
			var sub := Node3D.new()
			sub.transform = child.transform
			dest_parent.add_child(sub)
			_clone_meshes(child, sub)


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

	for c in _ghost_root.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = c.material_override
			var col := mat.albedo_color
			col.a = 0.45 * intensity
			mat.albedo_color = col
