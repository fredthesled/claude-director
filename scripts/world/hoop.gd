extends Node3D
class_name Hoop
## Backboard + rim + a thin Area3D "made basket" sensor just under the rim.
## Counts a basket when the ball passes downward through that sensor.

const RIM_HEIGHT := 3.05 # 10ft, in meters
const RIM_RADIUS := 0.23

const DoubleVisionGhost = preload("res://scripts/fx/double_vision_ghost.gd")

var _sensor: Area3D
var _cooldown: float = 0.0


func _ready() -> void:
	_build_visuals()
	_build_sensor()

	var ghost := DoubleVisionGhost.new()
	ghost.target = self
	ghost.max_offset = 0.15
	add_child(ghost)


func _build_visuals() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.15, 0.15, 0.17)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.1
	pole_mesh.height = RIM_HEIGHT + 0.5
	pole.mesh = pole_mesh
	pole.position = Vector3(0, (RIM_HEIGHT + 0.5) / 2.0, -0.6)
	pole.material_override = pole_mat
	add_child(pole)

	var backboard := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.8, 1.05, 0.05)
	backboard.mesh = board_mesh
	backboard.position = Vector3(0, RIM_HEIGHT + 0.4, -0.55)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.95, 0.95, 0.92, 0.85)
	board_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	backboard.material_override = board_mat
	add_child(backboard)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = RIM_RADIUS - 0.02
	rim_mesh.outer_radius = RIM_RADIUS
	rim.mesh = rim_mesh
	rim.position = Vector3(0, RIM_HEIGHT, 0)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.9, 0.25, 0.1)
	rim.material_override = rim_mat
	add_child(rim)

	var rim_collider := StaticBody3D.new()
	rim_collider.collision_layer = 1
	var rim_shape := CollisionShape3D.new()
	var torus_approx := CylinderShape3D.new()
	torus_approx.radius = RIM_RADIUS
	torus_approx.height = 0.06
	rim_shape.shape = torus_approx
	rim_shape.position = Vector3(0, RIM_HEIGHT, 0)
	rim_collider.add_child(rim_shape)
	add_child(rim_collider)


func _build_sensor() -> void:
	_sensor = Area3D.new()
	_sensor.collision_layer = 1 << 4 # layer 5 hoop_sensor
	_sensor.collision_mask = 1 << 3 # only watches for the ball (layer 4)
	_sensor.monitoring = true
	_sensor.monitorable = false

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RIM_RADIUS - 0.04
	cyl.height = 0.12
	shape.shape = cyl
	_sensor.add_child(shape)
	_sensor.position = Vector3(0, RIM_HEIGHT - 0.05, 0)
	add_child(_sensor)

	_sensor.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _cooldown > 0.0:
		return
	if not body is Basketball:
		return
	var ball: Basketball = body
	if ball.linear_velocity.y >= 0.0:
		return # only count it on the way down, not bouncing up off the rim
	if GameManager.state != GameManager.State.PLAYING:
		return

	_cooldown = 1.5
	GameManager.register_basket(ball.last_holder_team, global_position + Vector3(0, RIM_HEIGHT, 0))


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


## World position used by AI/player aiming logic.
func get_rim_target() -> Vector3:
	return global_position + Vector3(0, RIM_HEIGHT, 0)
