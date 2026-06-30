extends Node3D
class_name CharacterFace
## Procedural cartoony face built from primitives, mounted on a character's
## head. No external art needed: expressions are achieved by swapping mesh
## shapes / scales / colors at runtime, PEAK-style (big eyes, broad reactions).

enum FaceExpression { NEUTRAL, FOCUSED, HAPPY, SHOCKED, DRUNK }

var _left_eye: Node3D
var _right_eye: Node3D
var _left_pupil: MeshInstance3D
var _right_pupil: MeshInstance3D
var _left_brow: MeshInstance3D
var _right_brow: MeshInstance3D
var _mouth: MeshInstance3D
var _drool: MeshInstance3D

var _expression: FaceExpression = FaceExpression.NEUTRAL
var _drunk_amount: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	_left_eye = _build_eye(Vector3(-0.13, 0.04, 0.27))
	_right_eye = _build_eye(Vector3(0.13, 0.04, 0.27))
	_left_pupil = _left_eye.get_node("Pupil")
	_right_pupil = _right_eye.get_node("Pupil")

	_left_brow = _build_brow(Vector3(-0.13, 0.16, 0.27))
	_right_brow = _build_brow(Vector3(0.13, 0.16, 0.27))

	_mouth = MeshInstance3D.new()
	_mouth.mesh = TorusMesh.new()
	_mouth.mesh.inner_radius = 0.03
	_mouth.mesh.outer_radius = 0.07
	_mouth.position = Vector3(0.0, -0.12, 0.29)
	_mouth.rotation_degrees = Vector3(90, 0, 0)
	_mouth.material_override = _solid_material(Color(0.25, 0.05, 0.08))
	add_child(_mouth)

	_drool = MeshInstance3D.new()
	_drool.mesh = SphereMesh.new()
	_drool.mesh.radius = 0.025
	_drool.mesh.height = 0.05
	_drool.position = Vector3(0.05, -0.18, 0.28)
	_drool.material_override = _solid_material(Color(0.75, 0.92, 1.0, 0.85))
	_drool.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drool.visible = false
	add_child(_drool)

	set_expression(FaceExpression.NEUTRAL)


func _build_eye(local_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = local_pos
	add_child(root)

	var white := MeshInstance3D.new()
	white.mesh = SphereMesh.new()
	white.mesh.radius = 0.065
	white.mesh.height = 0.13
	white.material_override = _solid_material(Color.WHITE)
	root.add_child(white)

	var pupil := MeshInstance3D.new()
	pupil.name = "Pupil"
	pupil.mesh = SphereMesh.new()
	pupil.mesh.radius = 0.03
	pupil.mesh.height = 0.06
	pupil.position = Vector3(0, 0, 0.045)
	pupil.material_override = _solid_material(Color(0.05, 0.05, 0.08))
	root.add_child(pupil)

	return root


func _build_brow(local_pos: Vector3) -> MeshInstance3D:
	var brow := MeshInstance3D.new()
	brow.mesh = BoxMesh.new()
	brow.mesh.size = Vector3(0.16, 0.025, 0.02)
	brow.position = local_pos
	brow.material_override = _solid_material(Color(0.2, 0.12, 0.08))
	add_child(brow)
	return brow


func _solid_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


func set_expression(expr: FaceExpression, drunk_amount: float = 0.0) -> void:
	_expression = expr
	_drunk_amount = drunk_amount

	match expr:
		FaceExpression.NEUTRAL:
			_left_eye.scale = Vector3.ONE
			_right_eye.scale = Vector3.ONE
			_left_brow.rotation_degrees = Vector3.ZERO
			_right_brow.rotation_degrees = Vector3.ZERO
			_mouth.scale = Vector3(1, 1, 1)
			_drool.visible = false
		FaceExpression.FOCUSED:
			_left_eye.scale = Vector3(1.0, 0.65, 1.0)
			_right_eye.scale = Vector3(1.0, 0.65, 1.0)
			_left_brow.rotation_degrees = Vector3(0, 0, 12)
			_right_brow.rotation_degrees = Vector3(0, 0, -12)
			_mouth.scale = Vector3(0.7, 0.4, 1.0)
			_drool.visible = false
		FaceExpression.HAPPY:
			_left_eye.scale = Vector3(1.0, 0.8, 1.0)
			_right_eye.scale = Vector3(1.0, 0.8, 1.0)
			_left_brow.rotation_degrees = Vector3(0, 0, -8)
			_right_brow.rotation_degrees = Vector3(0, 0, 8)
			_mouth.scale = Vector3(1.4, 1.0, 1.0)
			_mouth.position.y = -0.1
			_drool.visible = false
		FaceExpression.SHOCKED:
			_left_eye.scale = Vector3(1.3, 1.3, 1.3)
			_right_eye.scale = Vector3(1.3, 1.3, 1.3)
			_left_brow.position.y = 0.21
			_right_brow.position.y = 0.21
			_mouth.scale = Vector3(1.2, 1.6, 1.2)
			_drool.visible = false
		FaceExpression.DRUNK:
			_left_eye.scale = Vector3(1.0, 0.55, 1.0)
			_right_eye.scale = Vector3(1.0, 0.55, 1.0)
			_left_brow.rotation_degrees = Vector3(0, 0, 20)
			_right_brow.rotation_degrees = Vector3(0, 0, -5)
			_mouth.scale = Vector3(0.9, 0.6, 1.0)
			_drool.visible = drunk_amount > 0.15


func _process(delta: float) -> void:
	if _expression != FaceExpression.DRUNK or _drunk_amount <= 0.0:
		return
	_t += delta
	# Cross-eyed wobble + drool stretch scale with how "far gone" this replay is.
	var cross := 0.05 * _drunk_amount
	_left_pupil.position.x = cross + sin(_t * 3.0) * 0.01 * _drunk_amount
	_right_pupil.position.x = -cross - sin(_t * 3.0 + 0.4) * 0.01 * _drunk_amount
	if _drool.visible:
		_drool.scale.y = 1.0 + abs(sin(_t * 2.0)) * 2.0 * _drunk_amount
