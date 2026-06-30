extends CharacterBodyBase
class_name AiPlayer
## Simple offense/defense FSM. Offense: chase loose ball, space out near the
## hoop, shoot when open close enough. Defense: stick to an assigned
## opponent between them and the hoop, with a chance to poke the ball away.

const SPEED := 4.0
const SHOOT_RANGE := 4.5
const STEAL_RANGE := 1.2

@export var ball_path: NodePath
@export var hoop_path: NodePath
@export var offense_spot: Vector3 = Vector3.ZERO # local offset near the hoop used when this AI is on offense without the ball
@export var mark_index: int = 0 # which opposing player this AI guards on defense

var ball: Basketball
var hoop: Hoop
var _shoot_cooldown: float = 0.0
var _steal_cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	super._physics_process(delta)

	if ball == null and ball_path != NodePath():
		ball = get_node_or_null(ball_path)
	if hoop == null and hoop_path != NodePath():
		hoop = get_node_or_null(hoop_path)
	if ball == null or hoop == null:
		return

	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_steal_cooldown = maxf(0.0, _steal_cooldown - delta)

	var on_offense := team == GameManager.possession
	if on_offense:
		_run_offense(delta)
	else:
		_run_defense(delta)

	move_and_slide()


func _run_offense(_delta: float) -> void:
	if has_ball:
		var dist_to_hoop := global_position.distance_to(hoop.get_rim_target())
		if dist_to_hoop < SHOOT_RANGE and _shoot_cooldown <= 0.0 and randf() < 0.02:
			if face:
				face.set_expression(face.FaceExpression.HAPPY)
			ball.shoot(hoop.get_rim_target())
			_shoot_cooldown = 2.0
			velocity.x = 0
			velocity.z = 0
			return
		_move_toward(hoop.get_rim_target() + Vector3(0, 0, 2.5), SPEED * 0.6)
	elif ball.held_by == null:
		_move_toward(ball.global_position, SPEED)
		if global_position.distance_to(ball.global_position) < 0.9:
			ball.pick_up(self)
	else:
		var target := hoop.global_position + offense_spot
		_move_toward(target, SPEED * 0.7)
		if face:
			face.set_expression(face.FaceExpression.NEUTRAL)


func _run_defense(_delta: float) -> void:
	var opponents := _get_team_actors(GameManager.opposing_team(team))
	var mark: CharacterBodyBase = opponents[mark_index % opponents.size()] if not opponents.is_empty() else null

	if ball.held_by != null and ball.held_by.team != team and global_position.distance_to(ball.held_by.global_position) < STEAL_RANGE:
		if face:
			face.set_expression(face.FaceExpression.FOCUSED)
		if _steal_cooldown <= 0.0 and randf() < 0.01:
			ball.pick_up(self)
			_steal_cooldown = 1.0
			return

	if mark != null:
		var to_hoop := (hoop.get_rim_target() - mark.global_position).normalized()
		var guard_spot := mark.global_position + to_hoop * 1.2
		_move_toward(guard_spot, SPEED * 0.85)
	elif ball.held_by == null:
		_move_toward(ball.global_position, SPEED * 0.85)


func _move_toward(target: Vector3, speed: float) -> void:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 0.3:
		velocity.x = 0
		velocity.z = 0
		return
	var dir := to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 10.0 * get_physics_process_delta_time())


func _get_team_actors(t: int) -> Array:
	var result: Array = []
	for id in ReplayManager.get_actors():
		var node = ReplayManager.get_actor(id)
		if node is CharacterBodyBase and node.team == t:
			result.append(node)
	return result
