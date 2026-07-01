extends Node3D
class_name Court
## Half-court (single hoop, streetball-style 3-on-3) built from primitives.

const COURT_WIDTH := 11.0
const COURT_LENGTH := 14.0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	add_child(floor_body)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(COURT_WIDTH, COURT_LENGTH)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.72, 0.5, 0.3)
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)

	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COURT_WIDTH, 0.2, COURT_LENGTH)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)

	_build_wall(Vector3(-COURT_WIDTH / 2.0 - 0.25, 1.5, 0), Vector3(0.5, 3.0, COURT_LENGTH))
	_build_wall(Vector3(COURT_WIDTH / 2.0 + 0.25, 1.5, 0), Vector3(0.5, 3.0, COURT_LENGTH))
	_build_wall(Vector3(0, 1.5, -COURT_LENGTH / 2.0 - 0.25), Vector3(COURT_WIDTH, 3.0, 0.5))
	_build_wall(Vector3(0, 1.5, COURT_LENGTH / 2.0 + 0.25), Vector3(COURT_WIDTH, 3.0, 0.5))

	var key_mesh := MeshInstance3D.new()
	var key_plane := PlaneMesh.new()
	key_plane.size = Vector2(4.9, 5.8)
	key_mesh.mesh = key_plane
	key_mesh.position = Vector3(0, 0.01, -COURT_LENGTH / 2.0 + 3.5)
	var key_mat := StandardMaterial3D.new()
	key_mat.albedo_color = Color(0.65, 0.42, 0.22)
	key_mesh.material_override = key_mat
	add_child(key_mesh)


func _build_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	add_child(body)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.55, 0.3)
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
