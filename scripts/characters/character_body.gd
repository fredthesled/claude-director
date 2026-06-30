extends CharacterBody3D
class_name CharacterBodyBase
## Shared chibi/cartoony character: oversized head + face, capsule torso,
## simple swinging limbs. Both the human PlayerController and AiPlayer extend
## this. Built entirely from primitives in code (PEAK-style "blobby cartoon
## with expressive face", no external art assets).

const GRAVITY := 18.0
const TEAM_A_COLOR := Color(0.2, 0.45, 0.95)
const TEAM_B_COLOR := Color(0.92, 0.25, 0.25)

@export var team: int = GameManager.Team.A
@export var actor_id: String = ""

var face: CharacterFace
var hand_marker: Marker3D
var has_ball: bool = false

var _legs: Array = []
var _arms: Array = []
var _walk_t: float = 0.0
var _drunk_visual_amount: float = 0.0

const DoubleVisionGhost = preload("res://scripts/fx/double_vision_ghost.gd")


func _ready() -> void:
	collision_layer = (1 << 1) if team == GameManager.Team.A else (1 << 2)
	collision_mask = 1 # world only; characters don't need to collide with each other

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.1
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.75
	add_child(col)

	_build_visuals()

	if actor_id == "":
		actor_id = name
	ReplayManager.register_actor(actor_id, self)


func _exit_tree() -> void:
	ReplayManager.unregister_actor(actor_id)


func _build_visuals() -> void:
	var team_color := TEAM_A_COLOR if team == GameManager.Team.A else TEAM_B_COLOR
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = team_color
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.96, 0.8, 0.65)

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.3
	torso_mesh.height = 0.9
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 0.75, 0)
	torso.material_override = body_mat
	add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.34
	head_mesh.height = 0.68
	head.mesh = head_mesh
	head.position = Vector3(0, 1.45, 0)
	head.material_override = skin_mat
	add_child(head)

	face = CharacterFace.new()
	face.name = "Face"
	head.add_child(face)

	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.1
		leg_mesh.height = 0.55
		leg.mesh = leg_mesh
		leg.position = Vector3(0.16 * side, 0.27, 0)
		leg.material_override = body_mat
		add_child(leg)
		_legs.append(leg)

		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.08
		arm_mesh.height = 0.5
		arm.mesh = arm_mesh
		arm.position = Vector3(0.42 * side, 0.95, 0)
		arm.material_override = skin_mat
		add_child(arm)
		_arms.append(arm)

	hand_marker = Marker3D.new()
	hand_marker.name = "HandMarker"
	hand_marker.position = Vector3(0.42, 0.7, 0.32)
	add_child(hand_marker)

	var ghost := DoubleVisionGhost.new()
	ghost.target = self
	ghost.max_offset = 0.1
	add_child(ghost)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_animate_limbs(delta)


func _animate_limbs(delta: float) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed > 0.2:
		_walk_t += delta * (4.0 + planar_speed)
	var swing := sin(_walk_t) * clampf(planar_speed / 5.0, 0.0, 1.0) * 0.5
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	if _arms.size() == 2 and not has_ball:
		_arms[0].rotation.x = -swing
		_arms[1].rotation.x = swing


## Called by the ReplayCameraRig while this actor is being scrubbed through
## recorded history, scaled by current psychedelic intensity. Drives the
## "drunk/high/stumbling" replay-only look.
func apply_drunk_visual(amount: float) -> void:
	_drunk_visual_amount = amount
	if face and face.has_method("set_expression"):
		if amount > 0.5:
			face.set_expression(face.FaceExpression.DRUNK, amount)
		elif amount > 0.15:
			face.set_expression(face.FaceExpression.SHOCKED, amount)
