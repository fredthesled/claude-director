extends Camera3D
class_name ReplayCameraRig
## The instant-replay camera: a sideline POV (not the player's own camera)
## that scrubs through the last few recorded seconds around a made shot.
## Crucially, this view does NOT run the psychedelic post-process (that's
## forced off globally while ReplayManager.is_replaying is true) — but the
## *players themselves* get progressively drunker/stumbling/drooling here,
## scaled by how far the game's psychedelic intensity has climbed.

const PLAYBACK_SPEED := 0.65
const SIDELINE_OFFSET := Vector3(9.0, 4.5, 1.5)


func _ready() -> void:
	current = false
	ReplayManager.replay_requested.connect(_play_replay)


func _play_replay(frames: Array, shot_pos: Vector3, _shot_team: int) -> void:
	if frames.is_empty():
		ReplayManager.finish_replay()
		return

	var actors := ReplayManager.get_actors()
	var live_transforms := {}
	var ball_was_frozen := {}
	for id in actors:
		if is_instance_valid(actors[id]):
			live_transforms[id] = actors[id].global_transform
			if actors[id] is Basketball:
				ball_was_frozen[id] = actors[id].freeze
				actors[id].freeze = true

	get_tree().call_group("game_camera", "set", "current", false)
	current = true
	global_position = shot_pos + SIDELINE_OFFSET
	look_at(shot_pos, Vector3.UP)

	var intensity: float = GameManager.psychedelic_intensity

	for i in range(frames.size()):
		var frame: Dictionary = frames[i]
		_apply_frame(frame, actors, intensity)

		var dt := 1.0 / 60.0
		if i + 1 < frames.size():
			dt = maxf(0.001, frames[i + 1]["t"] - frame["t"])
		await get_tree().create_timer(dt / PLAYBACK_SPEED).timeout

		if not is_instance_valid(self):
			return

	# Restore everyone to where they actually were when we paused live play.
	for id in live_transforms:
		if is_instance_valid(actors.get(id)):
			actors[id].global_transform = live_transforms[id]
		if actors.get(id) is CharacterBodyBase:
			actors[id].apply_drunk_visual(0.0)
		elif actors.get(id) is Basketball and ball_was_frozen.has(id):
			actors[id].freeze = ball_was_frozen[id]

	current = false
	get_tree().call_group("game_camera", "set", "current", true)
	ReplayManager.finish_replay()


func _apply_frame(frame: Dictionary, actors: Dictionary, intensity: float) -> void:
	var t: float = frame["t"]
	var players: Dictionary = frame["players"]
	for id in players:
		var node = actors.get(id)
		if not is_instance_valid(node):
			continue

		var recorded: Transform3D = players[id]

		if node is Basketball:
			node.global_transform = recorded
			continue

		if node is CharacterBodyBase and intensity > 0.01:
			var phase := float(id.hash() % 1000) * 0.01
			var stumble := sin(t * 6.0 + phase) * intensity * 0.4
			var bob := absf(sin(t * 9.0 + phase)) * intensity * 0.12
			var tilt := sin(t * 4.0 + phase * 1.3) * intensity * 0.35

			var basis := recorded.basis.rotated(recorded.basis.z.normalized(), tilt)
			var offset := recorded.basis.x.normalized() * stumble + Vector3(0, bob, 0)
			node.global_transform = Transform3D(basis, recorded.origin + offset)
			node.apply_drunk_visual(intensity)
		else:
			node.global_transform = recorded
