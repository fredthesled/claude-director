extends Node
## Continuously records the transforms of registered actors (players + ball)
## into a rolling history buffer. When GameManager reports a made basket, it
## waits a couple seconds (still recording the follow-through), then hands a
## window of recorded frames off to whoever is listening for `replay_requested`
## (the ReplayCameraRig) and freezes live gameplay until that finishes.

const HISTORY_SECONDS := 9.0
const PRE_SHOT_SECONDS := 5.0
const POST_SHOT_SECONDS := 2.0

signal replay_requested(frames: Array, shot_pos: Vector3, shot_team: int)
signal replay_ended

var is_replaying: bool = false

var _actors: Dictionary = {} # id:String -> Node3D
var _history: Array = []     # Array[Dictionary] { t: float, ball: Transform3D, players: Dictionary[String, Transform3D] }
var _elapsed: float = 0.0
var _resume_state: int = GameManager.State.PLAYING


func _ready() -> void:
	GameManager.shot_made.connect(_on_shot_made)


func register_actor(id: String, node: Node3D) -> void:
	_actors[id] = node


func unregister_actor(id: String) -> void:
	_actors.erase(id)


func get_actor(id: String) -> Node3D:
	return _actors.get(id)


func get_actors() -> Dictionary:
	return _actors


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if GameManager.state != GameManager.State.PLAYING:
		return

	var frame := { "t": _elapsed, "players": {} }
	for id in _actors:
		var node: Node3D = _actors[id]
		if is_instance_valid(node):
			frame["players"][id] = node.global_transform
	_history.append(frame)

	while _history.size() > 0 and _history[0]["t"] < _elapsed - HISTORY_SECONDS:
		_history.pop_front()


func _on_shot_made(scoring_team: int, world_pos: Vector3) -> void:
	_resume_state = GameManager.state
	await get_tree().create_timer(POST_SHOT_SECONDS).timeout

	var end_t: float = _elapsed
	var start_t: float = maxf(0.0, end_t - PRE_SHOT_SECONDS - POST_SHOT_SECONDS)
	var window: Array = _history.filter(func(f): return f["t"] >= start_t)

	if window.is_empty():
		return

	GameManager.state = GameManager.State.REPLAY
	GameManager.state_changed.emit(GameManager.State.REPLAY)
	is_replaying = true
	replay_requested.emit(window, world_pos, scoring_team)


## Called by ReplayCameraRig once playback finishes.
func finish_replay() -> void:
	is_replaying = false
	GameManager.state = _resume_state
	GameManager.state_changed.emit(_resume_state)
	replay_ended.emit()
