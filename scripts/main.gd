extends Node3D
## Assembles the whole game: court, hoop, ball, the human player, 5 AI
## teammates/opponents, lighting, the replay rig, the psychedelic overlay and
## the HUD. Everything is built procedurally in code — no hand-authored
## sub-scenes required.

const CourtScript = preload("res://scripts/world/court.gd")
const HoopScript = preload("res://scripts/world/hoop.gd")
const BallScript = preload("res://scripts/ball/basketball.gd")
const PlayerControllerScript = preload("res://scripts/characters/player_controller.gd")
const AiPlayerScript = preload("res://scripts/characters/ai_player.gd")
const ReplayCameraRigScript = preload("res://scripts/world/replay_camera_rig.gd")
const PsychedelicOverlayScript = preload("res://scripts/fx/psychedelic_overlay.gd")
const HudScript = preload("res://scripts/ui/hud.gd")

var hoop: Hoop
var ball: Basketball


func _ready() -> void:
	GameManager.reset_game()

	_build_environment()
	var court := CourtScript.new()
	add_child(court)

	hoop = HoopScript.new()
	hoop.position = Vector3(0, 0, -6.3)
	add_child(hoop)

	ball = BallScript.new()
	ball.position = Vector3(0, 1.0, 3.0)
	add_child(ball)

	var player := _spawn_player(Vector3(0, 0.1, 3.0))
	var ai_a1 := _spawn_ai(GameManager.Team.A, "ai_a1", Vector3(-2.5, 0.1, 3.5), Vector3(-2.5, 0, 3.0), 0)
	var ai_a2 := _spawn_ai(GameManager.Team.A, "ai_a2", Vector3(2.5, 0.1, 3.5), Vector3(2.5, 0, 3.0), 1)

	var ai_b1 := _spawn_ai(GameManager.Team.B, "ai_b1", Vector3(-2.0, 0.1, -3.0), Vector3(-2.5, 0, 3.0), 0)
	var ai_b2 := _spawn_ai(GameManager.Team.B, "ai_b2", Vector3(2.0, 0.1, -3.0), Vector3(2.5, 0, 3.0), 1)
	var ai_b3 := _spawn_ai(GameManager.Team.B, "ai_b3", Vector3(0.0, 0.1, -4.5), Vector3(0.0, 0, 4.0), 2)

	for ai in [ai_a1, ai_a2, ai_b1, ai_b2, ai_b3]:
		ai.ball_path = ai.get_path_to(ball)
		ai.hoop_path = ai.get_path_to(hoop)
	player.ball_path = player.get_path_to(ball)
	player.hoop_path = player.get_path_to(hoop)

	# Tip-off: the human player starts with the ball.
	ball.pick_up(player)

	var replay_rig := ReplayCameraRigScript.new()
	add_child(replay_rig)

	var overlay := PsychedelicOverlayScript.new()
	add_child(overlay)

	var hud := HudScript.new()
	add_child(hud)


func _spawn_player(spawn_pos: Vector3) -> PlayerController:
	var player := PlayerControllerScript.new()
	player.name = "Player"
	player.position = spawn_pos
	add_child(player)
	return player


func _spawn_ai(team: int, id: String, spawn_pos: Vector3, offense_spot: Vector3, mark_index: int) -> AiPlayer:
	var ai := AiPlayerScript.new()
	ai.name = id
	ai.team = team
	ai.actor_id = id
	ai.offense_spot = offense_spot
	ai.mark_index = mark_index
	ai.position = spawn_pos
	add_child(ai)
	return ai


func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
