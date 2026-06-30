extends RigidBody3D
class_name Basketball
## The ball. When held, it's kinematically glued to the holder's hand marker.
## When shot, physics takes over with an impulse aimed to arc into the hoop.

const RADIUS := 0.18
const BALL_LAYER_BIT := 1 << 3 # layer 4 "ball"
const WORLD_MASK := (1 << 0) | (1 << 1) | (1 << 2) # world + team_a + team_b (for steals via Area later)

var held_by: CharacterBodyBase = null
var last_holder_team: int = GameManager.Team.A

const DoubleVisionGhost = preload("res://scripts/fx/double_vision_ghost.gd")


func _ready() -> void:
	collision_layer = BALL_LAYER_BIT
	collision_mask = 1 # only collide with the floor/world by default

	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.45, 0.12)
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = RADIUS
	shape.shape = sphere_shape
	add_child(shape)

	mass = 0.6
	gravity_scale = 1.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.55
	physics_material_override.friction = 0.6

	ReplayManager.register_actor("ball", self)

	var ghost := DoubleVisionGhost.new()
	ghost.target = self
	ghost.max_offset = 0.08
	add_child(ghost)


func _exit_tree() -> void:
	ReplayManager.unregister_actor("ball")


func _physics_process(_delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if held_by != null and is_instance_valid(held_by):
		freeze = true
		global_position = held_by.hand_marker.global_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func pick_up(by: CharacterBodyBase) -> void:
	if held_by == by:
		return
	if held_by != null and is_instance_valid(held_by):
		held_by.has_ball = false
	held_by = by
	by.has_ball = true
	last_holder_team = by.team
	freeze = true


func release_loose() -> void:
	if held_by != null and is_instance_valid(held_by):
		held_by.has_ball = false
	held_by = null
	freeze = false


## Shoots the ball toward `target_pos` with an arcing trajectory.
func shoot(target_pos: Vector3, arc_height: float = 2.5) -> void:
	release_loose()
	var start := global_position
	var to_target := target_pos - start
	var flat_dist := Vector2(to_target.x, to_target.z).length()
	var time_to_target := clampf(flat_dist / 6.0, 0.35, 1.4)

	var vx := to_target.x / time_to_target
	var vz := to_target.z / time_to_target
	var g: float = -float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Solve for vy so the ball reaches target_pos.y at time_to_target with an arc.
	var vy: float = (to_target.y - 0.5 * g * time_to_target * time_to_target) / time_to_target
	vy += arc_height # extra lift for a satisfying arc, tunable

	linear_velocity = Vector3(vx, vy, vz)
	angular_velocity = Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
