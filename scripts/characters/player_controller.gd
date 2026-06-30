extends CharacterBodyBase
class_name PlayerController
## Human-controlled player. Camera-relative WASD movement, hold-to-aim
## shoot/pass, and a steal attempt when defending close to the ball carrier.

const SPEED := 4.5
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 5.5
const STEAL_RANGE := 1.3

@export var ball_path: NodePath
@export var hoop_path: NodePath

var ball: Basketball
var hoop: Hoop
var spring_arm: SpringArm3D
var camera: Camera3D


func _ready() -> void:
	team = GameManager.Team.A
	actor_id = "player"
	super._ready()
	add_to_group("game_camera_holder")

	spring_arm = SpringArm3D.new()
	spring_arm.position = Vector3(0, 1.6, 0)
	spring_arm.rotation_degrees = Vector3(-15, 0, 0)
	spring_arm.spring_length = 6.0
	add_child(spring_arm)

	camera = Camera3D.new()
	camera.add_to_group("game_camera")
	spring_arm.add_child(camera)
	camera.current = true


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	super._physics_process(delta)
	if ball == null and ball_path != NodePath():
		ball = get_node_or_null(ball_path)
	if hoop == null and hoop_path != NodePath():
		hoop = get_node_or_null(hoop_path)

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)

	var cam_basis := camera.global_transform.basis if camera else Basis.IDENTITY
	var forward := -cam_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0
	right = right.normalized()

	var move_dir := (right * input_dir.x + forward * input_dir.y)
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	var speed := SPRINT_SPEED if Input.is_action_pressed("action_sprint") else SPEED
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	if move_dir.length_squared() > 0.001:
		var look_dir := move_dir.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(look_dir.x, look_dir.z), 12.0 * delta)

	if is_on_floor() and Input.is_action_just_pressed("action_jump"):
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	if face:
		face.set_expression(face.FaceExpression.FOCUSED if has_ball else face.FaceExpression.NEUTRAL)

	_handle_ball_actions()


func _handle_ball_actions() -> void:
	if ball == null:
		return

	if has_ball:
		if Input.is_action_just_pressed("action_shoot") and hoop != null:
			if face:
				face.set_expression(face.FaceExpression.HAPPY)
			ball.shoot(hoop.get_rim_target())
		elif Input.is_action_just_pressed("action_pass"):
			var teammate := _find_nearest_teammate()
			if teammate:
				ball.pick_up(teammate)
	else:
		if ball.held_by == null and global_position.distance_to(ball.global_position) < 1.1:
			ball.pick_up(self)
		elif Input.is_action_just_pressed("action_pass") and ball.held_by != null and ball.held_by.team != team:
			if global_position.distance_to(ball.held_by.global_position) < STEAL_RANGE and randf() < 0.35:
				ball.pick_up(self)


func _find_nearest_teammate() -> CharacterBodyBase:
	var best: CharacterBodyBase = null
	var best_dist := INF
	for id in ReplayManager.get_actors():
		var node = ReplayManager.get_actor(id)
		if node is CharacterBodyBase and node != self and node.team == team:
			var d := global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = node
	return best
